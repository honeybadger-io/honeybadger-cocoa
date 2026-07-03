#pragma once

#include <stdint.h>
#include <mach/machine.h>

// On-disk / in-memory representation of one loaded Mach-O image. Fixed-size,
// pointer-free, and memcpy-safe: the signal handler persists this struct
// verbatim with write(), and the next launch reads it back. Field order and
// sizes are part of the crash-file format (see HB_SIGNAL_CRASH_VERSION).
#define HB_MAX_BINARY_IMAGES 512

typedef struct {
    char          name[512];
    uint8_t       uuid[16];
    uint8_t       has_uuid;
    uint8_t       _pad[7];
    uint64_t      load_address;
    uint64_t      vmaddr_slide;
    cpu_type_t    cpu_type;
    cpu_subtype_t cpu_subtype;
} HBBinaryImage;
