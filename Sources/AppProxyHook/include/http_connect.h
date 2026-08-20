#ifndef HTTP_CONNECT_H
#define HTTP_CONNECT_H

#include "hook_common.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    char host[256];
    int port;
    char auth_basic[512]; // Base64 basic auth string if configured
    bool is_configured;
} ProxyEndpoint;

// Loads proxy settings from APPMANAGER_PROXY_* environment variables
void http_proxy_init(void);

// Gets the active proxy endpoint
const ProxyEndpoint *http_proxy_get_endpoint(void);

// Returns true if the address represents localhost/loopback or the proxy itself
bool http_proxy_is_bypass(const struct sockaddr *addr);

// Establishes an HTTP CONNECT tunnel on `sockfd` to `target_host:target_port`
int http_proxy_establish_tunnel(int sockfd, const char *target_host, uint16_t target_port);

#ifdef __cplusplus
}
#endif

#endif // HTTP_CONNECT_H
