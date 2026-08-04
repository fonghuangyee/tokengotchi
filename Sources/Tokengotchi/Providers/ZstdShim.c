//
//  ZstdShim.c
//  Tokengotchi
//
//  Thin wrapper around the vendored zstd decoder, exposing a stable C ABI to
//  Swift via ZstdShim.h. Compiled together with the zstd sources in
//  Providers/zstd/.
//

#include "ZstdShim.h"
#include <stdlib.h>
#include "zstd/zstd.h"

long tok_zstd_decompress(const void *src, size_t srcSize, void *dst, size_t dstCapacity) {
    size_t r = ZSTD_decompress(dst, dstCapacity, src, srcSize);
    if (ZSTD_isError(r)) { return -1; }
    return (long)r;
}

long tok_zstd_decompress_alloc(const void *src, size_t srcSize, void **outBuf) {
    *outBuf = NULL;

    // Fast path: use the declared content size when the frame provides one.
    unsigned long long cs = ZSTD_getFrameContentSize(src, srcSize);
    if (cs != ZSTD_CONTENTSIZE_UNKNOWN && cs != ZSTD_CONTENTSIZE_ERROR && cs > 0) {
        void *buf = malloc((size_t)cs);
        if (!buf) { return -1; }
        size_t r = ZSTD_decompress(buf, (size_t)cs, src, srcSize);
        if (ZSTD_isError(r)) { free(buf); return -1; }
        *outBuf = buf;
        return (long)r;
    }

    // General path: stream into a growable buffer.
    ZSTD_DCtx *dctx = ZSTD_createDCtx();
    if (!dctx) { return -1; }

    size_t cap = 1 << 20; /* 1 MB initial */
    size_t outLen = 0;
    unsigned char *out = malloc(cap);
    if (!out) { ZSTD_freeDCtx(dctx); return -1; }

    ZSTD_inBuffer ib = { src, srcSize, 0 };
    while (ib.pos < ib.size) {
        if (outLen == cap) {
            cap *= 2;
            unsigned char *nb = realloc(out, cap);
            if (!nb) { free(out); ZSTD_freeDCtx(dctx); return -1; }
            out = nb;
        }
        ZSTD_outBuffer ob = { out + outLen, cap - outLen, 0 };
        size_t r = ZSTD_decompressStream(dctx, &ob, &ib);
        if (ZSTD_isError(r)) { free(out); ZSTD_freeDCtx(dctx); return -1; }
        outLen += ob.pos;
    }

    ZSTD_freeDCtx(dctx);
    *outBuf = out;
    return (long)outLen;
}
