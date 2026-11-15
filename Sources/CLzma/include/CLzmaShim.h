#ifndef PHEXT_CLZMA_SHIM_H
#define PHEXT_CLZMA_SHIM_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* xz-encode `in_len` bytes at the given preset with LZMA_CHECK_CRC64
 * (the libphext seal format: preset 6 + CRC64, matching libphext-rs's
 * xz2 encoder). On success returns 0 and sets *out / *out_len to a
 * malloc'd buffer the caller must release with phext_xz_free().
 * On failure returns a nonzero lzma_ret code. */
int phext_xz_encode(const uint8_t *in, size_t in_len, uint32_t preset,
                    uint8_t **out, size_t *out_len);

/* xz-decode a complete xz stream. Same ownership contract as encode. */
int phext_xz_decode(const uint8_t *in, size_t in_len,
                    uint8_t **out, size_t *out_len);

void phext_xz_free(uint8_t *ptr);

/* XXH3-128 of `in_len` bytes, written as low 64 bits then high 64 bits
 * (matching xxhash-rust's xxh3_128 return value's low/high fields).
 * Returns 0 on success, -1 when libxxhash is unavailable at runtime. */
int phext_xxh3_128(const uint8_t *in, size_t in_len,
                   uint64_t *low, uint64_t *high);

#ifdef __cplusplus
}
#endif

#endif
