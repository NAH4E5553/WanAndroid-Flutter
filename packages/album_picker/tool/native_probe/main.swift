import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: directory) }
func expect(_ condition: Bool, _ message: String) {
    if !condition { fatalError(message) }
}
let color = CGColorSpace(name: CGColorSpace.sRGB)!
let context = CGContext(data: nil, width: 8, height: 4, bitsPerComponent: 8, bytesPerRow: 0, space: color, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
context.fill(CGRect(x: 4, y: 0, width: 4, height: 4))
let image = context.makeImage()!
for orientation in 1...8 {
    let input = directory.appendingPathComponent("source\(orientation).jpg")
    let output = directory.appendingPathComponent("output\(orientation).png")
    let destination = CGImageDestinationCreateWithURL(input as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation,
        kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 1, kCGImagePropertyGPSLongitude: 1]] as CFDictionary)
    expect(CGImageDestinationFinalize(destination), "fixture encoding")
    let result: (Int, Int, Int)
    do { result = try ImageExport.normalize(source: input, destination: output, inputLimit: 100000, outputLimit: 100000, maxDimension: 100, maxPixels: 10000, task: ExportTask(seconds: 10)) }
    catch {
        if let source = CGImageSourceCreateWithURL(output as CFURL, nil), let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) {
            print("Controlled probe properties: \(properties)")
        }
        print("Controlled probe failure: \(error)")
        exit(1)
    }
    expect(result.0 == (orientation >= 5 ? 4 : 8) && result.1 == (orientation >= 5 ? 8 : 4), "orientation dimensions")
    let encoded = try Data(contentsOf: output)
    var offset = 8
    while offset + 12 <= encoded.count {
        let length = encoded[offset..<offset+4].reduce(0) { ($0 << 8) | Int($1) }
        let chunk = String(data: encoded[offset+4..<offset+8], encoding: .ascii)!
        expect(!["eXIf", "tEXt", "iTXt", "zTXt"].contains(chunk), "no source metadata chunks")
        offset += 12 + length
    }
    let src = CGImageSourceCreateWithURL(output as CFURL, nil)!
    let properties = CGImageSourceCopyPropertiesAtIndex(src, 0, nil)! as NSDictionary
    expect(properties[kCGImagePropertyGPSDictionary] == nil, "GPS stripped")
    expect(properties[kCGImagePropertyOrientation] == nil || (properties[kCGImagePropertyOrientation] as? Int) == 1, "upright")
}
let input = directory.appendingPathComponent("source1.jpg")
func rejects(_ expected: String, _ block: () throws -> Void) {
    do { try block(); fatalError("expected failure: \(expected)") }
    catch { expect((error as? ExportFailure)?.code == expected, "wrong failure \(error)") }
}
rejects("budgetExceeded") { _ = try ImageExport.normalize(source: input, destination: directory.appendingPathComponent("small.png"), inputLimit: 100000, outputLimit: 1, maxDimension: 100, maxPixels: 10000, task: ExportTask(seconds: 10)) }
rejects("budgetExceeded") { _ = try ImageExport.normalize(source: input, destination: directory.appendingPathComponent("large.png"), inputLimit: 100000, outputLimit: 100000, maxDimension: 4, maxPixels: 10000, task: ExportTask(seconds: 10)) }
let cancelled = ExportTask(seconds: 10); cancelled.cancel()
rejects("cancelled") { _ = try ImageExport.normalize(source: input, destination: directory.appendingPathComponent("cancel.png"), inputLimit: 100000, outputLimit: 100000, maxDimension: 100, maxPixels: 10000, task: cancelled) }
expect(FileManager.default.fileExists(atPath: input.path), "source intact")
print("ImageIO probe passed: 8 orientation dimensions, metadata removal, bounded PNG output, predecode dimensions, cancellation, source preservation. macOS evidence, not PhotoKit/iOS device evidence.")

if CommandLine.arguments.count > 1 {
    let seeds = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    try FileManager.default.createDirectory(at: seeds, withIntermediateDirectories: true)
    for name in ["source6.jpg", "output1.png"] {
        let destination = seeds.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
        try FileManager.default.copyItem(at: directory.appendingPathComponent(name), to: destination)
    }
}
