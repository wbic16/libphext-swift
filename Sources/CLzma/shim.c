#include "CLzmaShim.h"

#include <stdlib.h>
#include <string.h>
#include <dlfcn.h>
#include <lzma.h>

int phext_xz_encode(const uint8_t *in, size_t in_len, uint32_t preset,
                    uint8_t **out, size_t *out_len) {
    lzma_stream strm = LZMA_STREAM_INIT;
    lzma_ret ret = lzma_easy_encoder(&strm, preset, LZMA_CHECK_CRC64);
    if (ret != LZMA_OK) {
        return (int)ret;
    }
    /* Generous upper bound: xz of incompressible data grows only slightly. */
    size_t cap = in_len + in_len / 3 + 128 * 1024;
    uint8_t *buf = (uint8_t *)malloc(cap);
    if (buf == NULL) {
        lzma_end(&strm);
        return (int)LZMA_MEM_ERROR;
    }
    strm.next_in = in;
    strm.avail_in = in_len;
    strm.next_out = buf;
    strm.avail_out = cap;
    ret = lzma_code(&strm, LZMA_FINISH);
    size_t produced = cap - strm.avail_out;
    lzma_end(&strm);
    if (ret != LZMA_STREAM_END) {
        free(buf);
        return (int)(ret == LZMA_OK ? LZMA_DATA_ERROR : ret);
    }
    *out = buf;
    *out_len = produced;
    return 0;
}

int phext_xz_decode(const uint8_t *in, size_t in_len,
                    uint8_t **out, size_t *out_len) {
    lzma_stream strm = LZMA_STREAM_INIT;
    lzma_ret ret = lzma_stream_decoder(&strm, UINT64_MAX, 0);
    if (ret != LZMA_OK) {
        return (int)ret;
    }
    size_t cap = in_len * 4 + 65536;
    uint8_t *buf = (uint8_t *)malloc(cap);
    if (buf == NULL) {
        lzma_end(&strm);
        return (int)LZMA_MEM_ERROR;
    }
    strm.next_in = in;
    strm.avail_in = in_len;
    strm.next_out = buf;
    strm.avail_out = cap;
    while (1) {
        ret = lzma_code(&strm, LZMA_FINISH);
        if (ret == LZMA_STREAM_END) {
            break;
        }
        if (ret != LZMA_OK) {
            free(buf);
            lzma_end(&strm);
            return (int)ret;
        }
        /* Output buffer full but stream not ended: grow and continue. */
        size_t produced = cap - strm.avail_out;
        size_t new_cap = cap * 2;
        uint8_t *grown = (uint8_t *)realloc(buf, new_cap);
        if (grown == NULL) {
            free(buf);
            lzma_end(&strm);
            return (int)LZMA_MEM_ERROR;
        }
        buf = grown;
        strm.next_out = buf + produced;
        strm.avail_out = new_cap - produced;
        cap = new_cap;
    }
    *out_len = cap - strm.avail_out;
    *out = buf;
    lzma_end(&strm);
    return 0;
}

void phext_xz_free(uint8_t *ptr) {
    free(ptr);
}

/* XXH3_128bits from libxxhash, resolved at runtime so the package builds
 * on hosts that ship only the libxxhash runtime (no -dev package).
 * The XXH128_hash_t layout is { XXH64_hash_t low64, high64 } in that
 * order on all platforms libxxhash supports. */
typedef struct {
    uint64_t low64;
    uint64_t high64;
} phext_xxh128_t;
typedef phext_xxh128_t (*phext_xxh3_128_fn)(const void *, size_t);

int phext_xxh3_128(const uint8_t *in, size_t in_len,
                   uint64_t *low, uint64_t *high) {
    static phext_xxh3_128_fn fn = NULL;
    static int resolved = 0;
    if (!resolved) {
        resolved = 1;
        void *handle = dlopen("libxxhash.so.0", RTLD_LAZY);
        if (handle == NULL) {
            handle = dlopen("libxxhash.so", RTLD_LAZY);
        }
        if (handle != NULL) {
            fn = (phext_xxh3_128_fn)dlsym(handle, "XXH3_128bits");
        }
    }
    if (fn == NULL) {
        return -1;
    }
    phext_xxh128_t hash = fn(in, in_len);
    *low = hash.low64;
    *high = hash.high64;
    return 0;
}
