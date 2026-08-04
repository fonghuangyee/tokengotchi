import Foundation

// MARK: - Zstandard decompression (vendored decoder)
//
// Zed persists agent threads as zstd-compressed JSON blobs in `threads.db`.
// macOS ships no linkable libzstd, so we vendor the reference decoder (see
// `Providers/zstd/`) and call it through the small C shim in `ZstdShim.c`.
// This file is the Swift-facing facade.
enum Zstd {

    enum ZstdError: Error {
        case decompressionFailed
    }

    /// Decompress a complete zstd frame to raw bytes. Throws on malformed input.
    static func decompress(_ data: Data) throws -> Data {
        try data.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Data in
            guard let srcBase = src.baseAddress else { throw ZstdError.decompressionFailed }
            var outBuf: UnsafeMutableRawPointer? = nil
            let size = tok_zstd_decompress_alloc(srcBase, src.count, &outBuf)
            guard size >= 0, let buf = outBuf else { throw ZstdError.decompressionFailed }
            // Take ownership of the malloc'd buffer; free after copying into Data.
            defer { free(buf) }
            return Data(bytes: buf, count: Int(size))
        }
    }
}
