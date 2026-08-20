#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <unistd.h>
#include <dlfcn.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <fcntl.h>
#include <errno.h>

#define APPMANAGER_HOOK_VERSION "1.1.0"

// Logging helper
static inline void hook_log(const char *fmt, ...) {
    const char *debug = getenv("APPMANAGER_HOOK_DEBUG");
    if (debug && (strcmp(debug, "1") == 0 || strcasecmp(debug, "true") == 0)) {
        va_list args;
        va_start(args, fmt);
        fprintf(stderr, "[AppProxyHook] ");
        vfprintf(stderr, fmt, args);
        fprintf(stderr, "\n");
        va_end(args);
    }
}

#if defined(__APPLE__)
#define REAL_CONNECT connect
#else
typedef int (*connect_func)(int, const struct sockaddr *, socklen_t);
static connect_func original_connect = NULL;
#define REAL_CONNECT original_connect
#endif

// Base64 encoding for Basic Auth
static const char b64_table[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

static void base64_encode(const char *src, char *dst, size_t dst_len) {
    size_t src_len = strlen(src);
    size_t i = 0, j = 0;

    while (i < src_len && (j + 4) < dst_len) {
        uint32_t octet_a = i < src_len ? (unsigned char)src[i++] : 0;
        uint32_t octet_b = i < src_len ? (unsigned char)src[i++] : 0;
        uint32_t octet_c = i < src_len ? (unsigned char)src[i++] : 0;

        uint32_t triple = (octet_a << 16) + (octet_b << 8) + octet_c;

        dst[j++] = b64_table[(triple >> 18) & 0x3F];
        dst[j++] = b64_table[(triple >> 12) & 0x3F];
        dst[j++] = (i > src_len + 1) ? '=' : b64_table[(triple >> 6) & 0x3F];
        dst[j++] = (i > src_len) ? '=' : b64_table[triple & 0x3F];
    }
    dst[j] = '\0';
}

int my_connect(int sockfd, const struct sockaddr *addr, socklen_t addrlen) {
#if !defined(__APPLE__)
    if (!original_connect) {
        original_connect = (connect_func)dlsym(RTLD_NEXT, "connect");
    }
#endif

    if (!addr) {
        return REAL_CONNECT(sockfd, addr, addrlen);
    }

    // Only intercept IPv4 connections
    if (addr->sa_family != AF_INET) {
        return REAL_CONNECT(sockfd, addr, addrlen);
    }

    const struct sockaddr_in *target_addr = (const struct sockaddr_in *)addr;

    // Resolve Proxy IP and Port from environment
    const char *proxy_ip_str = getenv("APPMANAGER_PROXY_HOST");
    if (!proxy_ip_str) proxy_ip_str = getenv("GOPEN_IP");

    const char *proxy_port_str = getenv("APPMANAGER_PROXY_PORT");
    if (!proxy_port_str) proxy_port_str = getenv("GOPEN_PORT");

    if (!proxy_ip_str || !proxy_port_str) {
        // Check HTTP_PROXY
        const char *http_proxy = getenv("HTTP_PROXY");
        if (!http_proxy) http_proxy = getenv("http_proxy");
        if (!http_proxy) http_proxy = getenv("ALL_PROXY");
        if (!http_proxy) http_proxy = getenv("all_proxy");

        if (http_proxy && strlen(http_proxy) > 0) {
            static char parsed_host[128] = {0};
            static char parsed_port[16] = "7890";
            const char *p = http_proxy;
            if (strncmp(p, "http://", 7) == 0) p += 7;
            else if (strncmp(p, "https://", 8) == 0) p += 8;

            const char *at = strchr(p, '@');
            if (at) p = at + 1;

            const char *colon = strchr(p, ':');
            if (colon) {
                size_t host_len = (size_t)(colon - p);
                if (host_len < sizeof(parsed_host)) {
                    strncpy(parsed_host, p, host_len);
                    strncpy(parsed_port, colon + 1, sizeof(parsed_port) - 1);
                }
            } else {
                strncpy(parsed_host, p, sizeof(parsed_host) - 1);
            }
            proxy_ip_str = parsed_host;
            proxy_port_str = parsed_port;
        }
    }

    if (!proxy_ip_str || !proxy_port_str || strlen(proxy_ip_str) == 0) {
        return REAL_CONNECT(sockfd, addr, addrlen);
    }

    // Avoid proxying loopback / local connections
    uint32_t target_ip = ntohl(target_addr->sin_addr.s_addr);
    if ((target_ip & 0xFF000000) == 0x7F000000 || target_ip == 0 || target_ip == 0xFFFFFFFF) {
        return REAL_CONNECT(sockfd, addr, addrlen);
    }

    // Prepare proxy address
    struct sockaddr_in proxy_addr;
    memset(&proxy_addr, 0, sizeof(proxy_addr));
    proxy_addr.sin_family = AF_INET;
    proxy_addr.sin_port = htons((uint16_t)atoi(proxy_port_str));
    if (inet_pton(AF_INET, proxy_ip_str, &proxy_addr.sin_addr) <= 0) {
        struct hostent *he = gethostbyname(proxy_ip_str);
        if (!he || !he->h_addr_list[0]) {
            return REAL_CONNECT(sockfd, addr, addrlen);
        }
        memcpy(&proxy_addr.sin_addr, he->h_addr_list[0], sizeof(struct in_addr));
    }

    // Avoid double-proxying if target is already the proxy server
    if (target_addr->sin_addr.s_addr == proxy_addr.sin_addr.s_addr &&
        target_addr->sin_port == proxy_addr.sin_port) {
        return REAL_CONNECT(sockfd, addr, addrlen);
    }

    // Check if socket is non-blocking
    int flags = fcntl(sockfd, F_GETFL, 0);
    int is_nonblocking = (flags >= 0) && ((flags & O_NONBLOCK) != 0);

    // Temporarily make socket blocking for the HTTP CONNECT handshake
    if (is_nonblocking) {
        fcntl(sockfd, F_SETFL, flags & ~O_NONBLOCK);
    }

    // Set a short handshake timeout so we never hang indefinitely
    struct timeval tv = { .tv_sec = 3, .tv_usec = 0 };
    setsockopt(sockfd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    setsockopt(sockfd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));

    // Connect to proxy server
    hook_log("Intercepted connect() -> routing to proxy %s:%s", proxy_ip_str, proxy_port_str);
    int res = REAL_CONNECT(sockfd, (struct sockaddr *)&proxy_addr, sizeof(proxy_addr));
    if (res < 0) {
        hook_log("Failed to connect to proxy: errno %d (%s)", errno, strerror(errno));
        if (is_nonblocking) fcntl(sockfd, F_SETFL, flags);
        return res;
    }

    // Extract target IP and port
    char target_ip_str[INET_ADDRSTRLEN];
    inet_ntop(AF_INET, &(target_addr->sin_addr), target_ip_str, INET_ADDRSTRLEN);
    int target_port = ntohs(target_addr->sin_port);

    // Optional proxy authentication header
    char auth_header[256] = {0};
    const char *auth_env = getenv("APPMANAGER_PROXY_AUTH");
    if (auth_env && strlen(auth_env) > 0) {
        char b64[192] = {0};
        base64_encode(auth_env, b64, sizeof(b64));
        snprintf(auth_header, sizeof(auth_header), "Proxy-Authorization: Basic %s\r\n", b64);
    }

    // Construct HTTP CONNECT request
    char req[512];
    int req_len = snprintf(req, sizeof(req),
        "CONNECT %s:%d HTTP/1.1\r\n"
        "Host: %s:%d\r\n"
        "User-Agent: AppManagerProxyHook/%s\r\n"
        "Proxy-Connection: Keep-Alive\r\n"
        "%s\r\n",
        target_ip_str, target_port,
        target_ip_str, target_port,
        APPMANAGER_HOOK_VERSION,
        auth_header
    );

    if (send(sockfd, req, (size_t)req_len, 0) < 0) {
        hook_log("Failed to send HTTP CONNECT request");
        if (is_nonblocking) fcntl(sockfd, F_SETFL, flags);
        return -1;
    }

    // Read response (looking for "HTTP/1.x 200")
    char resp[1024];
    int total_read = 0;
    while (total_read < (int)sizeof(resp) - 1) {
        ssize_t n = recv(sockfd, resp + total_read, 1, 0);
        if (n <= 0) {
            break;
        }
        total_read += (int)n;
        resp[total_read] = '\0';
        if (strstr(resp, "\r\n\r\n")) {
            break;
        }
    }

    // Clear timeouts
    struct timeval zero_tv = { .tv_sec = 0, .tv_usec = 0 };
    setsockopt(sockfd, SOL_SOCKET, SO_RCVTIMEO, &zero_tv, sizeof(zero_tv));
    setsockopt(sockfd, SOL_SOCKET, SO_SNDTIMEO, &zero_tv, sizeof(zero_tv));

    // Restore non-blocking state if original socket was non-blocking
    if (is_nonblocking) {
        fcntl(sockfd, F_SETFL, flags);
    }

    if (!strstr(resp, "HTTP/1.1 200") && !strstr(resp, "HTTP/1.0 200") && !strstr(resp, "HTTP/2 200")) {
        hook_log("Proxy rejected CONNECT:\n%s", resp);
        errno = ECONNREFUSED;
        return -1;
    }

    hook_log("Tunnel established successfully to %s:%d", target_ip_str, target_port);
    return 0;
}

#if defined(__APPLE__)
#define DYLD_INTERPOSE(_replacement,_replacee) \
   __attribute__((used)) static struct{ const void* replacement; const void* replacee; } _interpose_##_replacee \
   __attribute__((section ("__DATA,__interpose"))) = { (const void*)(unsigned long)&_replacement, (const void*)(unsigned long)&_replacee };
DYLD_INTERPOSE(my_connect, connect)
#endif
