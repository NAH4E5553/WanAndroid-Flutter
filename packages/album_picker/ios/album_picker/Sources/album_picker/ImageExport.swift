import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

struct ExportFailure: Error {
    let code: String
    init(_ code: String) { self.code = code }
}

final class ExportTask {
    private let lock = NSLock()
    private var stopped = false
    private var cancelHandler: (() -> Void)?
    let deadline: TimeInterval
    init(seconds: Double) { deadline = ProcessInfo.processInfo.systemUptime + seconds }
    func check() throws {
        lock.lock(); let cancelled = stopped; lock.unlock()
        if cancelled { throw ExportFailure("cancelled") }
        if ProcessInfo.processInfo.systemUptime >= deadline { throw ExportFailure("timeout") }
    }
    func cancel() {
        lock.lock(); stopped = true; let callback = cancelHandler; lock.unlock()
        callback?()
    }
    func onCancel(_ callback: @escaping () -> Void) {
        lock.lock(); cancelHandler = callback; let cancelled = stopped; lock.unlock()
        if cancelled { callback() }
    }
}

/// Counts before every write, including the ImageIO encoder's callback.
/// FileHandle is owned here; no plugin or media-library path may be passed.
final class BoundedImageWriter {
    private let lock = NSLock()
    private var handle: FileHandle?
    private(set) var count = 0
    private(set) var failure: Error?
    private let limit: Int
    private let task: ExportTask
    init(url: URL, limit: Int, task: ExportTask) throws {
        self.limit = limit; self.task = task
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else { throw ExportFailure("writeFailed") }
        handle = try FileHandle(forWritingTo: url)
    }
    func write(_ data: Data) throws {
        lock.lock(); defer { lock.unlock() }
        do {
            try task.check()
            guard data.count <= limit - count else { throw ExportFailure("budgetExceeded") }
            guard let handle = handle else { throw ExportFailure("cancelled") }
            try handle.write(contentsOf: data); count += data.count
        } catch { failure = error; throw error }
    }
    func close() throws {
        lock.lock(); defer { lock.unlock() }
        if let handle = handle { try handle.synchronize(); try handle.close(); self.handle = nil }
    }
    deinit { try? handle?.close() }
    private var pngHeader = Data()
    private var pngSignature = true
    private var pngRemaining = 0
    private var pngKeep = false
    // ImageIO can synthesize an eXIf chunk even from a fresh CGImage.
    // Strip nonessential ancillary chunks during encoding, without a second
    // full file or unbounded accumulation of an IDAT chunk.
    private func writePNG(_ data: Data) throws {
        var offset = 0
        while offset < data.count {
            if pngRemaining > 0 {
                let count = min(pngRemaining, data.count - offset)
                if pngKeep { try write(data.subdata(in: offset..<offset+count)) }
                offset += count; pngRemaining -= count
                continue
            }
            let count = min(8 - pngHeader.count, data.count - offset)
            pngHeader.append(data.subdata(in: offset..<offset+count)); offset += count
            if pngHeader.count < 8 { continue }
            if pngSignature {
                guard Array(pngHeader) == [137,80,78,71,13,10,26,10] else { throw ExportFailure("encodeFailed") }
                try write(pngHeader); pngSignature = false
            } else {
                let length = pngHeader.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
                let kind = String(data: pngHeader.suffix(4), encoding: .ascii) ?? ""
                pngKeep = ["IHDR", "IDAT", "IEND", "sRGB", "gAMA", "cHRM", "iCCP", "tRNS"].contains(kind)
                pngRemaining = length + 4
                if pngKeep { try write(pngHeader) }
            }
            pngHeader.removeAll(keepingCapacity: true)
        }
    }
    func consumer() -> CGDataConsumer? {
        var callbacks = CGDataConsumerCallbacks(putBytes: { info, bytes, count in
            guard let info = info else { return 0 }
            let writer = Unmanaged<BoundedImageWriter>.fromOpaque(info).takeUnretainedValue()
            do { try writer.writePNG(Data(bytes: bytes, count: count)); return count }
            catch { return 0 }
        }, releaseConsumer: { info in
            if let info = info { Unmanaged<BoundedImageWriter>.fromOpaque(info).release() }
        })
        let retained = Unmanaged.passRetained(self).toOpaque()
        guard let consumer = CGDataConsumer(info: retained, cbks: &callbacks) else {
            Unmanaged<BoundedImageWriter>.fromOpaque(retained).release(); return nil
        }
        return consumer
    }
}

struct ImageExport {
    static func normalize(source: URL, destination: URL, inputLimit: Int, outputLimit: Int,
                          maxDimension: Int, maxPixels: Int, task: ExportTask) throws -> (Int, Int, Int) {
        try task.check()
        let size = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= inputLimit else { throw ExportFailure("budgetExceeded") }
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              let type = CGImageSourceGetType(imageSource) as String?,
              [UTType.jpeg.identifier, UTType.png.identifier, UTType.heic.identifier, UTType.heif.identifier, UTType.gif.identifier].contains(type)
        else { throw ExportFailure("unsupportedFormat") }
        try bounds(width, height, maxDimension, maxPixels)
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height),
            kCGImageSourceShouldCacheImmediately: true]
        try task.check()
        guard let image = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
            throw ExportFailure("unsupportedFormat")
        }
        try bounds(image.width, image.height, maxDimension, maxPixels)
        try task.check()
        guard let color = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                  bytesPerRow: 0, space: color, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw ExportFailure("decodeFailed") }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let normalized = context.makeImage() else { throw ExportFailure("decodeFailed") }
        let writer = try BoundedImageWriter(url: destination, limit: outputLimit, task: task)
        guard let consumer = writer.consumer(),
              let output = CGImageDestinationCreateWithDataConsumer(consumer, UTType.png.identifier as CFString, 1, nil)
        else { throw ExportFailure("writeFailed") }
        CGImageDestinationAddImage(output, normalized, nil)
        let success = CGImageDestinationFinalize(output)
        try writer.close()
        if let failure = writer.failure { throw failure }
        guard success, writer.count > 0 else { throw ExportFailure("encodeFailed") }
        try task.check()
        guard let verify = CGImageSourceCreateWithURL(destination as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let result = CGImageSourceCopyPropertiesAtIndex(verify, 0, nil) as? [CFString: Any],
              (result[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue == normalized.width,
              (result[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue == normalized.height,
              result[kCGImagePropertyGPSDictionary] == nil
        else { throw ExportFailure("invalidExport") }
        return (normalized.width, normalized.height, writer.count)
    }
    static func bounds(_ width: Int, _ height: Int, _ maxDimension: Int, _ maxPixels: Int) throws {
        guard width > 0, height > 0 else { throw ExportFailure("unsupportedFormat") }
        guard width <= maxDimension, height <= maxDimension, height <= maxPixels / width else { throw ExportFailure("budgetExceeded") }
    }
}
