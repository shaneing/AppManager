#include "hook_common.h"
#include "fake_dns.h"
#include "http_connect.h"

// Function pointer types
typedef int (*connect_func_t)(int, const struct sockaddr *, socklen_t);
typedef int (*connectx_func_t)(int, const sa_endpoints_t *, sae_associd_t, unsigned int, const struct iovec *, unsigned int, size_t *, sae_connid_t *);
typedef int (*getaddrinfo_func_t)(const char *, const char *, const struct addrinfo *, struct addrinfo **);
typedef void (*freeaddrinfo_func_t)(struct addrinfo *);

static connect_func_t orig_connect = NULL;
static connectx_func_t orig_connectx = NULL;
static getaddrinfo_func_t orig_getaddrinfo = NULL;
static freeaddrinfo_func_t orig_freeaddrinfo = NULL;

int real_connect(int sockfd, const struct sockaddr *addr, socklen_t addrlen) {
    if (!orig_connect) {
        orig_connect = (connect_func_t)dlsym(RTLD_NEXT, "connect");
        if (!orig_connect) {
            orig_connect = (connect_func_t)dlsym(RTLD_DEFAULT, "connect");
        }
    }
    return orig_connect ? orig_connect(sockfd, addr, addrlen) : -1;
}

int real_connectx(int s, const sa_endpoints_t *endpoints, sae_associd_t associd,
                  unsigned int flags, const struct iovec *iov, unsigned int iovcnt,
                  size_t *len, sae_connid_t *connid) {
    if (!orig_connectx) {
        orig_connectx = (connectx_func_t)dlsym(RTLD_NEXT, "connectx");
        if (!orig_connectx) {
            orig_connectx = (connectx_func_t)dlsym(RTLD_DEFAULT, "connectx");
        }
    }
    return orig_connectx ? orig_connectx(s, endpoints, associd, flags, iov, iovcnt, len, connid) : -1;
}

int real_getaddrinfo(const char *node, const char *service,
                     const struct addrinfo *hints, struct addrinfo **res) {
    if (!orig_getaddrinfo) {
        orig_getaddrinfo = (getaddrinfo_func_t)dlsym(RTLD_NEXT, "getaddrinfo");
        if (!orig_getaddrinfo) {
            orig_getaddrinfo = (getaddrinfo_func_t)dlsym(RTLD_DEFAULT, "getaddrinfo");
        }
    }
    return orig_getaddrinfo ? orig_getaddrinfo(node, service, hints, res) : EAI_FAIL;
}

void real_freeaddrinfo(struct addrinfo *ai) {
    if (!orig_freeaddrinfo) {
        orig_freeaddrinfo = (freeaddrinfo_func_t)dlsym(RTLD_NEXT, "freeaddrinfo");
        if (!orig_freeaddrinfo) {
            orig_freeaddrinfo = (freeaddrinfo_func_t)dlsym(RTLD_DEFAULT, "freeaddrinfo");
        }
    }
    if (orig_freeaddrinfo) {
        orig_freeaddrinfo(ai);
    }
}

// Hook implementations
int hook_connect(int sockfd, const struct sockaddr *addr, socklen_t addrlen) {
    if (!addr) {
        return real_connect(sockfd, addr, addrlen);
    }

    if (http_proxy_is_bypass(addr)) {
        return real_connect(sockfd, addr, addrlen);
    }

    if (addr->sa_family == AF_INET) {
        const struct sockaddr_in *in = (const struct sockaddr_in *)addr;
        uint16_t port = ntohs(in->sin_port);

        // Check for synthetic fake IP from getaddrinfo
        char hostname[256] = {0};
        if (fake_dns_reverse_lookup(in->sin_addr, hostname, sizeof(hostname))) {
            return http_proxy_establish_tunnel(sockfd, hostname, port);
        }

        // Direct IP connection
        char ip_str[INET_ADDRSTRLEN] = {0};
        inet_ntop(AF_INET, &(in->sin_addr), ip_str, sizeof(ip_str));
        return http_proxy_establish_tunnel(sockfd, ip_str, port);
    } else if (addr->sa_family == AF_INET6) {
        const struct sockaddr_in6 *in6 = (const struct sockaddr_in6 *)addr;
        uint16_t port = ntohs(in6->sin6_port);
        char ip6_str[INET6_ADDRSTRLEN] = {0};
        inet_ntop(AF_INET6, &(in6->sin6_addr), ip6_str, sizeof(ip6_str));
        return http_proxy_establish_tunnel(sockfd, ip6_str, port);
    }

    return real_connect(sockfd, addr, addrlen);
}

int hook_connectx(int s, const sa_endpoints_t *endpoints, sae_associd_t associd,
                  unsigned int flags, const struct iovec *iov, unsigned int iovcnt,
                  size_t *len, sae_connid_t *connid) {
    if (endpoints && endpoints->sae_dstaddr) {
        if (!http_proxy_is_bypass(endpoints->sae_dstaddr)) {
            int res = hook_connect(s, endpoints->sae_dstaddr, endpoints->sae_dstaddrlen);
            if (res == 0 && len) {
                *len = 0;
            }
            return res;
        }
    }
    return real_connectx(s, endpoints, associd, flags, iov, iovcnt, len, connid);
}

// Special magic value for synthetic addrinfo identification
#define SYNTHETIC_AI_CANARY 0x4150504D // "APPM"

typedef struct SyntheticAddrInfo {
    struct addrinfo ai;
    struct sockaddr_in sin;
    uint32_t canary;
} SyntheticAddrInfo;

int hook_getaddrinfo(const char *node, const char *service,
                     const struct addrinfo *hints, struct addrinfo **res) {
    if (!node || !res) {
        return real_getaddrinfo(node, service, hints, res);
    }

    // Attempt Fake-IP mapping for remote hostnames
    struct in_addr fake_addr;
    if (fake_dns_lookup_or_insert(node, &fake_addr)) {
        uint16_t port = 0;
        if (service) {
            int p = atoi(service);
            if (p > 0 && p <= 65535) {
                port = (uint16_t)p;
            } else {
                struct servent *se = getservbyname(service, "tcp");
                if (se) {
                    port = ntohs(se->s_port);
                }
            }
        }

        SyntheticAddrInfo *synth = (SyntheticAddrInfo *)calloc(1, sizeof(SyntheticAddrInfo));
        if (!synth) {
            return EAI_MEMORY;
        }

        synth->canary = SYNTHETIC_AI_CANARY;
        synth->sin.sin_family = AF_INET;
        synth->sin.sin_port = htons(port);
        synth->sin.sin_addr = fake_addr;

        synth->ai.ai_family = AF_INET;
        synth->ai.ai_socktype = (hints && hints->ai_socktype) ? hints->ai_socktype : SOCK_STREAM;
        synth->ai.ai_protocol = (hints && hints->ai_protocol) ? hints->ai_protocol : IPPROTO_TCP;
        synth->ai.ai_addrlen = sizeof(struct sockaddr_in);
        synth->ai.ai_addr = (struct sockaddr *)&synth->sin;
        synth->ai.ai_canonname = strdup(node);
        synth->ai.ai_next = NULL;

        *res = &synth->ai;
        hook_log("Intercepted getaddrinfo('%s') -> Fake IP 198.18.%u.%u",
                 node, (ntohl(fake_addr.s_addr) >> 8) & 0xFF, ntohl(fake_addr.s_addr) & 0xFF);
        return 0;
    }

    return real_getaddrinfo(node, service, hints, res);
}

void hook_freeaddrinfo(struct addrinfo *ai) {
    if (!ai) return;

    // Check if this was allocated by our hook_getaddrinfo
    SyntheticAddrInfo *synth = (SyntheticAddrInfo *)ai;
    if (synth->canary == SYNTHETIC_AI_CANARY) {
        if (synth->ai.ai_canonname) {
            free(synth->ai.ai_canonname);
        }
        free(synth);
        return;
    }

    real_freeaddrinfo(ai);
}

// Dyld interpose mapping tables
DYLD_INTERPOSE(hook_connect, connect)
DYLD_INTERPOSE(hook_connectx, connectx)
DYLD_INTERPOSE(hook_getaddrinfo, getaddrinfo)
DYLD_INTERPOSE(hook_freeaddrinfo, freeaddrinfo)
