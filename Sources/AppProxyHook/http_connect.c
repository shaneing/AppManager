#include "http_connect.h"

static ProxyEndpoint g_proxy = {
    .host = "127.0.0.1",
    .port = 7890,
    .auth_basic = "",
    .is_configured = false
};

static pthread_once_t proxy_init_once = PTHREAD_ONCE_INIT;

// Base64 encoding table
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

static void http_proxy_init_internal(void) {
    const char *host_env = getenv("APPMANAGER_PROXY_HOST");
    const char *port_env = getenv("APPMANAGER_PROXY_PORT");
    const char *auth_env = getenv("APPMANAGER_PROXY_AUTH");

    if (host_env && strlen(host_env) > 0) {
        strncpy(g_proxy.host, host_env, sizeof(g_proxy.host) - 1);
        g_proxy.is_configured = true;
    }

    if (port_env && strlen(port_env) > 0) {
        int p = atoi(port_env);
        if (p > 0 && p <= 65535) {
            g_proxy.port = p;
            g_proxy.is_configured = true;
        }
    }

    if (auth_env && strlen(auth_env) > 0) {
        char b64[384] = {0};
        base64_encode(auth_env, b64, sizeof(b64));
        snprintf(g_proxy.auth_basic, sizeof(g_proxy.auth_basic), "Proxy-Authorization: Basic %s\r\n", b64);
    }

    // Also check standard HTTP_PROXY if APPMANAGER_* is not explicitly set
    if (!g_proxy.is_configured) {
        const char *http_proxy = getenv("HTTP_PROXY");
        if (!http_proxy) http_proxy = getenv("http_proxy");
        if (!http_proxy) http_proxy = getenv("ALL_PROXY");
        if (!http_proxy) http_proxy = getenv("all_proxy");

        if (http_proxy && strlen(http_proxy) > 0) {
            // Simple URL parsing: [http://][user:pass@]host:port
            const char *p = http_proxy;
            if (strncmp(p, "http://", 7) == 0) p += 7;
            else if (strncmp(p, "https://", 8) == 0) p += 8;

            const char *at = strchr(p, '@');
            if (at) {
                char userpass[256] = {0};
                size_t userpass_len = (size_t)(at - p);
                if (userpass_len < sizeof(userpass)) {
                    strncpy(userpass, p, userpass_len);
                    char b64[384] = {0};
                    base64_encode(userpass, b64, sizeof(b64));
                    snprintf(g_proxy.auth_basic, sizeof(g_proxy.auth_basic), "Proxy-Authorization: Basic %s\r\n", b64);
                }
                p = at + 1;
            }

            char host_buf[256] = {0};
            int port = 7890;
            const char *colon = strchr(p, ':');
            if (colon) {
                size_t host_len = (size_t)(colon - p);
                if (host_len < sizeof(host_buf)) {
                    strncpy(host_buf, p, host_len);
                    port = atoi(colon + 1);
                }
            } else {
                strncpy(host_buf, p, sizeof(host_buf) - 1);
            }

            if (strlen(host_buf) > 0) {
                strncpy(g_proxy.host, host_buf, sizeof(g_proxy.host) - 1);
                g_proxy.port = (port > 0) ? port : 7890;
                g_proxy.is_configured = true;
            }
        }
    }

    hook_log("Proxy initialized -> %s:%d (active: %s)",
             g_proxy.host, g_proxy.port, g_proxy.is_configured ? "yes" : "no");
}

void http_proxy_init(void) {
    pthread_once(&proxy_init_once, http_proxy_init_internal);
}

const ProxyEndpoint *http_proxy_get_endpoint(void) {
    http_proxy_init();
    return &g_proxy;
}

bool http_proxy_is_bypass(const struct sockaddr *addr) {
    if (!addr) return true;

    http_proxy_init();

    if (addr->sa_family == AF_UNIX) {
        return true;
    }

    if (addr->sa_family == AF_INET) {
        const struct sockaddr_in *in = (const struct sockaddr_in *)addr;
        uint32_t ip = ntohl(in->sin_addr.s_addr);

        // 127.0.0.0/8 (Loopback)
        if ((ip & 0xFF000000) == 0x7F000000) {
            return true;
        }

        // 0.0.0.0
        if (ip == 0) {
            return true;
        }

        // 255.255.255.255
        if (ip == 0xFFFFFFFF) {
            return true;
        }

        // Check if connecting directly to proxy itself
        struct in_addr proxy_addr;
        if (inet_pton(AF_INET, g_proxy.host, &proxy_addr) == 1) {
            if (in->sin_addr.s_addr == proxy_addr.s_addr && ntohs(in->sin_port) == (uint16_t)g_proxy.port) {
                return true;
            }
        }
    } else if (addr->sa_family == AF_INET6) {
        const struct sockaddr_in6 *in6 = (const struct sockaddr_in6 *)addr;
        // ::1 loopback
        if (IN6_IS_ADDR_LOOPBACK(&in6->sin6_addr)) {
            return true;
        }
    }

    return false;
}

// Forward declaration of real connect
extern int real_connect(int sockfd, const struct sockaddr *addr, socklen_t addrlen);

int http_proxy_establish_tunnel(int sockfd, const char *target_host, uint16_t target_port) {
    if (!target_host || target_port == 0) {
        errno = EINVAL;
        return -1;
    }

    http_proxy_init();

    // Resolve proxy IP
    struct sockaddr_in proxy_sockaddr;
    memset(&proxy_sockaddr, 0, sizeof(proxy_sockaddr));
    proxy_sockaddr.sin_family = AF_INET;
    proxy_sockaddr.sin_port = htons((uint16_t)g_proxy.port);

    if (inet_pton(AF_INET, g_proxy.host, &proxy_sockaddr.sin_addr) != 1) {
        struct hostent *he = gethostbyname(g_proxy.host);
        if (!he || !he->h_addr_list[0]) {
            hook_log("Failed to resolve proxy host: %s", g_proxy.host);
            errno = EHOSTUNREACH;
            return -1;
        }
        memcpy(&proxy_sockaddr.sin_addr, he->h_addr_list[0], sizeof(struct in_addr));
    }

    // Connect to proxy server using the original connect
    hook_log("Connecting FD %d to proxy %s:%d (for %s:%u)...",
             sockfd, g_proxy.host, g_proxy.port, target_host, target_port);

    if (real_connect(sockfd, (const struct sockaddr *)&proxy_sockaddr, sizeof(proxy_sockaddr)) < 0) {
        hook_log("Failed to connect to proxy %s:%d (errno: %d - %s)",
                 g_proxy.host, g_proxy.port, errno, strerror(errno));
        return -1;
    }

    // Construct HTTP CONNECT request
    char req[1024];
    int req_len = snprintf(req, sizeof(req),
        "CONNECT %s:%u HTTP/1.1\r\n"
        "Host: %s:%u\r\n"
        "User-Agent: AppManagerProxyHook/%s\r\n"
        "Proxy-Connection: Keep-Alive\r\n"
        "%s"
        "\r\n",
        target_host, target_port,
        target_host, target_port,
        APPMANAGER_HOOK_VERSION,
        g_proxy.auth_basic
    );

    // Send CONNECT request
    ssize_t sent = 0;
    while (sent < req_len) {
        ssize_t n = send(sockfd, req + sent, (size_t)(req_len - sent), 0);
        if (n <= 0) {
            if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR)) {
                continue;
            }
            hook_log("Failed to send HTTP CONNECT request to proxy");
            return -1;
        }
        sent += n;
    }

    // Read HTTP response header line by line
    char resp_buf[2048];
    size_t resp_len = 0;
    bool header_ended = false;

    while (!header_ended && resp_len < sizeof(resp_buf) - 1) {
        char c;
        ssize_t n = recv(sockfd, &c, 1, 0);
        if (n <= 0) {
            if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR)) {
                continue;
            }
            hook_log("Proxy connection closed during CONNECT handshake");
            errno = ECONNRESET;
            return -1;
        }
        resp_buf[resp_len++] = c;
        if (resp_len >= 4 &&
            resp_buf[resp_len - 4] == '\r' && resp_buf[resp_len - 3] == '\n' &&
            resp_buf[resp_len - 2] == '\r' && resp_buf[resp_len - 1] == '\n') {
            header_ended = true;
        }
    }
    resp_buf[resp_len] = '\0';

    // Parse status code from "HTTP/1.x 200"
    int status_code = 0;
    if (sscanf(resp_buf, "HTTP/1.%*d %d", &status_code) == 1 ||
        sscanf(resp_buf, "HTTP/2 %d", &status_code) == 1) {
        if (status_code >= 200 && status_code < 300) {
            hook_log("Tunnel established -> %s:%u (status: %d)", target_host, target_port, status_code);
            return 0; // Success!
        }
    }

    hook_log("Proxy rejected CONNECT with status %d:\n%s", status_code, resp_buf);
    if (status_code == 407) {
        errno = EACCES; // Proxy Auth Required
    } else {
        errno = ECONNREFUSED;
    }
    return -1;
}
