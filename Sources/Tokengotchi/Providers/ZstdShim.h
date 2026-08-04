//
//  ZstdShim.h
//  Tokengotchi
//
//  Minimal bridging surface between Swift and the vendored zstd decoder.
//  Exposes only the two functions Tokengotchi needs; the zstd internals stay
//  out of the Swift importer to avoid macro collisions (DEBUG, MEM_STATIC).
//

#ifndef ZstdShim_h
#define ZstdShim_h

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Decompresses a complete zstd frame into `dst`.
/// Returns the number of bytes written (>= 0), or -1 on error.
/// `dstCapacity` must be large enough; call `tok_zstd_frame_content_size`
/// first when the size is known, otherwise grow-and-retry via the streaming
/// helper below.
long tok_zstd_decompress(const void *src, size_t srcSize, void *dst, size_t dstCapacity);

/// Decompresses a complete zstd frame of unknown output size, allocating the
/// result buffer with malloc. On success returns the decompressed size and
/// sets `*outBuf` (caller must free). Returns -1 on error.
long tok_zstd_decompress_alloc(const void *src, size_t srcSize, void **outBuf);

#ifdef __cplusplus
}
#endif

#endif /* ZstdShim_h */
