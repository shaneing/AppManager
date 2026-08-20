#ifndef HOOK_COMMON_H
#define HOOK_COMMON_H

#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <stdbool.h>
#include <stdint.h>
#include <errno.h>
#include <unistd.h>
#include <pthread.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <fcntl.h>
#include <dlfcn.h>

#define APPMANAGER_HOOK_VERSION "1.0.0"
#define LOG_PREFIX "[AppProxyHook] "

// Logging helper
static inline void hook_log(const char *fmt, ...) {
    const char *debug = getenv("APPMANAGER_HOOK_DEBUG");
    if (debug && (strcmp(debug, "1") == 0 || strcasecmp(debug, "true") == 0)) {
        va_list args;
        va_start(args, fmt);
        fprintf(stderr, LOG_PREFIX);
        vfprintf(stderr, fmt, args);
        fprintf(stderr, "\n");
        va_end(args);
    }
}

// Dyld interpose structure for macOS Mach-O
typedef struct interpose_s {
    const void *new_func;
    const void *orig_func;
} interpose_t;

#define DYLD_INTERPOSE(_replacement, _replacee) \
    __attribute__((used)) static const interpose_t interpose_##_replacee \
    __attribute__((section("__DATA,__interpose"))) = { \
        (const void *)(unsigned long)&_replacement, \
        (const void *)(unsigned long)&_replacee \
    };

#endif // HOOK_COMMON_H
