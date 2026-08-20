#include "fake_dns.h"

#define FAKE_IP_START 0xC6120001U // 198.18.0.1
#define FAKE_IP_END   0xC613FFFEU // 198.19.255.254
#define FAKE_IP_MASK  0xFFFE0000U // /15
#define FAKE_IP_NET   0xC6120000U // 198.18.0.0

#define HASH_TABLE_SIZE 2048

typedef struct FakeDnsEntry {
    uint32_t fake_ip; // host byte order
    char *hostname;
    struct FakeDnsEntry *next_by_name;
    struct FakeDnsEntry *next_by_ip;
} FakeDnsEntry;

static FakeDnsEntry *name_buckets[HASH_TABLE_SIZE] = {0};
static FakeDnsEntry *ip_buckets[HASH_TABLE_SIZE] = {0};
static uint32_t next_fake_ip = FAKE_IP_START;
static pthread_rwlock_t dns_rwlock = PTHREAD_RWLOCK_INITIALIZER;
static bool dns_initialized = false;

static unsigned int hash_string(const char *str) {
    unsigned int hash = 5381;
    int c;
    while ((c = *str++)) {
        hash = ((hash << 5) + hash) + (unsigned int)c;
    }
    return hash % HASH_TABLE_SIZE;
}

static unsigned int hash_ip(uint32_t ip) {
    return (ip ^ (ip >> 16)) % HASH_TABLE_SIZE;
}

void fake_dns_init(void) {
    pthread_rwlock_wrlock(&dns_rwlock);
    if (!dns_initialized) {
        memset(name_buckets, 0, sizeof(name_buckets));
        memset(ip_buckets, 0, sizeof(ip_buckets));
        next_fake_ip = FAKE_IP_START;
        dns_initialized = true;
    }
    pthread_rwlock_unlock(&dns_rwlock);
}

bool fake_dns_is_fake_ip(struct in_addr addr) {
    uint32_t host_ip = ntohl(addr.s_addr);
    return (host_ip & FAKE_IP_MASK) == FAKE_IP_NET;
}

bool fake_dns_lookup_or_insert(const char *hostname, struct in_addr *out_addr) {
    if (!hostname || !out_addr) {
        return false;
    }

    // Check if it's already an IPv4 dotted address
    struct in_addr dummy_addr;
    if (inet_pton(AF_INET, hostname, &dummy_addr) == 1) {
        return false;
    }
    // Check if it's an IPv6 address
    struct in6_addr dummy_addr6;
    if (inet_pton(AF_INET6, hostname, &dummy_addr6) == 1) {
        return false;
    }

    // Bypass localhost/local domain names
    if (strcasecmp(hostname, "localhost") == 0 ||
        strcasecmp(hostname, "localhost.localdomain") == 0 ||
        strcasecmp(hostname, "broadcasthost") == 0) {
        return false;
    }

    fake_dns_init();

    unsigned int name_idx = hash_string(hostname);

    // Read lock check
    pthread_rwlock_rdlock(&dns_rwlock);
    FakeDnsEntry *entry = name_buckets[name_idx];
    while (entry) {
        if (strcasecmp(entry->hostname, hostname) == 0) {
            out_addr->s_addr = htonl(entry->fake_ip);
            pthread_rwlock_unlock(&dns_rwlock);
            return true;
        }
        entry = entry->next_by_name;
    }
    pthread_rwlock_unlock(&dns_rwlock);

    // Upgrade to write lock for insertion
    pthread_rwlock_wrlock(&dns_rwlock);
    // Double-check under write lock
    entry = name_buckets[name_idx];
    while (entry) {
        if (strcasecmp(entry->hostname, hostname) == 0) {
            out_addr->s_addr = htonl(entry->fake_ip);
            pthread_rwlock_unlock(&dns_rwlock);
            return true;
        }
        entry = entry->next_by_name;
    }

    // Allocate new synthetic IP
    uint32_t assigned_ip = next_fake_ip++;
    if (next_fake_ip > FAKE_IP_END) {
        next_fake_ip = FAKE_IP_START; // Wrap around if pool exhausted
    }

    FakeDnsEntry *new_entry = (FakeDnsEntry *)malloc(sizeof(FakeDnsEntry));
    if (!new_entry) {
        pthread_rwlock_unlock(&dns_rwlock);
        return false;
    }

    new_entry->fake_ip = assigned_ip;
    new_entry->hostname = strdup(hostname);
    new_entry->next_by_name = name_buckets[name_idx];
    name_buckets[name_idx] = new_entry;

    unsigned int ip_idx = hash_ip(assigned_ip);
    new_entry->next_by_ip = ip_buckets[ip_idx];
    ip_buckets[ip_idx] = new_entry;

    out_addr->s_addr = htonl(assigned_ip);
    hook_log("Mapped '%s' -> 198.18.%u.%u", hostname, (assigned_ip >> 8) & 0xFF, assigned_ip & 0xFF);

    pthread_rwlock_unlock(&dns_rwlock);
    return true;
}

bool fake_dns_reverse_lookup(struct in_addr addr, char *out_hostname, size_t maxlen) {
    if (!out_hostname || maxlen == 0) {
        return false;
    }

    uint32_t host_ip = ntohl(addr.s_addr);
    if ((host_ip & FAKE_IP_MASK) != FAKE_IP_NET) {
        return false;
    }

    fake_dns_init();

    unsigned int ip_idx = hash_ip(host_ip);

    pthread_rwlock_rdlock(&dns_rwlock);
    FakeDnsEntry *entry = ip_buckets[ip_idx];
    while (entry) {
        if (entry->fake_ip == host_ip) {
            strncpy(out_hostname, entry->hostname, maxlen - 1);
            out_hostname[maxlen - 1] = '\0';
            pthread_rwlock_unlock(&dns_rwlock);
            return true;
        }
        entry = entry->next_by_ip;
    }
    pthread_rwlock_unlock(&dns_rwlock);

    return false;
}
