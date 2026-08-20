#ifndef FAKE_DNS_H
#define FAKE_DNS_H

#include "hook_common.h"

#ifdef __cplusplus
extern "C" {
#endif

// Initialize the in-memory Fake IP map
void fake_dns_init(void);

// Assigns or retrieves a synthetic IPv4 address (198.18.0.0/15) for the given hostname
bool fake_dns_lookup_or_insert(const char *hostname, struct in_addr *out_addr);

// Performs reverse lookup for a synthetic IP to retrieve the original hostname
bool fake_dns_reverse_lookup(struct in_addr addr, char *out_hostname, size_t maxlen);

// Checks if an IPv4 address falls within the synthetic Fake-IP range (198.18.0.0/15)
bool fake_dns_is_fake_ip(struct in_addr addr);

#ifdef __cplusplus
}
#endif

#endif // FAKE_DNS_H
