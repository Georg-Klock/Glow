// check-week-plates.swift
//
// Verifies the plates make-week-plates.swift wrote, with the decoder the
// browsers actually use rather than the one that wrote them.
//
// Apple's decoder is lenient: the first word-slider plates opened in Preview,
// measured correctly through Core Image, and were refused outright by libavif
// (`Invalid image grid`), so Chrome drew nothing. This runs `avifdec` (libavif)
// on every file and fails when any plate is not what the page needs:
//
//   * even width and height (MIAF 4:2:0 grid rule)
//   * 10-bit, no alpha plane
//   * colour primaries 9 (BT.2020) and transfer 16 (PQ) — the tags that make
//     the browser paint it in extended range
//   * a decoded peak above SDR white (203 nits), i.e. the file is HDR in its
//     pixels, not only in its tags
//   * every file the manifest names exists
//
// With `--preview DIR` it also writes an 8-bit tone-mapped PNG of each plate,
// scaled up, for looking at the shapes on a screen without headroom. Those are
// for geometry only; they cannot show the glow.
//
// Usage:
//   swift Tools/check-week-plates.swift --dir Website/week-widget/assets [--preview /tmp/previews]
//
// Needs `avifdec` (brew install libavif).

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func arg(_ name: String, _ fallback: String) -> String {
    let args = CommandLine.arguments
    guard let i = args.firstIndex(of: "--\(name)"), i + 1 < args.count else { return fallback }
    return args[i + 1]
}

let root = URL(fileURLWithPath: arg("dir", "Website/week-widget/assets"), isDirectory: true)
let previewDir = arg("preview", "")
let sdrWhite = 203.0

guard let avifdec = ["/opt/homebrew/bin/avifdec", "/usr/local/bin/avifdec"]
    .first(where: { FileManager.default.isExecutableFile(atPath: $0) })
else {
    print("avifdec not found — brew install libavif")
    exit(2)
}

@discardableResult
func run(_ tool: String, _ arguments: [String]) -> (status: Int32, output: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: tool)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try! process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, String(decoding: data, as: UTF8.self))
}

/// PQ EOTF, code value in 0...1 to nits (SMPTE ST 2084).
func pqToNits(_ e: Double) -> Double {
    let m1 = 0.1593017578125, m2 = 78.84375
    let c1 = 0.8359375, c2 = 18.8515625, c3 = 18.6875
    let ep = pow(e, 1 / m2)
    return pow(max(ep - c1, 0) / (c2 - c3 * ep), 1 / m1) * 10000
}

struct Failure: Error, CustomStringConvertible {
    let description: String
}

func check(_ file: URL, gain: Double, preview: URL?) throws -> String {
    let info = run(avifdec, ["--info", file.path])
    guard info.status == 0 else {
        throw Failure(description: "avifdec refused it: \(info.output.trimmingCharacters(in: .whitespacesAndNewlines))")
    }
    func field(_ name: String) -> String? {
        info.output.split(separator: "\n")
            .first { $0.contains("* \(name)") }?
            .split(separator: ":", maxSplits: 1).last?
            .trimmingCharacters(in: .whitespaces)
    }
    guard let resolution = field("Resolution"),
          let dims = Optional(resolution.split(separator: "x").compactMap { Int($0) }), dims.count == 2
    else { throw Failure(description: "no resolution in avifdec output") }
    let (width, height) = (dims[0], dims[1])
    if width % 2 != 0 || height % 2 != 0 {
        throw Failure(description: "odd dimensions \(width)x\(height) — libavif refuses an odd 4:2:0 grid")
    }
    guard field("Bit Depth") == "10" else { throw Failure(description: "bit depth \(field("Bit Depth") ?? "?"), expected 10") }
    guard field("Alpha") == "Absent" else { throw Failure(description: "carries an alpha plane") }
    guard field("Color Primaries") == "9" else { throw Failure(description: "primaries \(field("Color Primaries") ?? "?"), expected 9 (BT.2020)") }
    guard field("Transfer Char.") == "16" else { throw Failure(description: "transfer \(field("Transfer Char.") ?? "?"), expected 16 (PQ)") }

    // Decode the pixels with libavif too, to 16-bit PNG, and read the raw codes.
    let png = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
    defer { try? FileManager.default.removeItem(at: png) }
    let decode = run(avifdec, ["-d", "16", file.path, png.path])
    guard decode.status == 0 else { throw Failure(description: "avifdec could not decode the pixels") }
    guard let source = CGImageSourceCreateWithURL(png as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
          let data = image.dataProvider?.data as Data?
    else { throw Failure(description: "could not read the decoded PNG") }
    let components = image.bitsPerPixel / image.bitsPerComponent
    guard image.bitsPerComponent == 16 else { throw Failure(description: "decoded PNG is \(image.bitsPerComponent)-bit") }
    let bigEndian = image.byteOrderInfo == .order16Big || image.byteOrderInfo == .orderDefault

    var peakCode: UInt16 = 0
    var codes = [UInt16](repeating: 0, count: width * height)
    data.withUnsafeBytes { raw in
        for y in 0..<height {
            let row = raw.baseAddress!.advanced(by: y * image.bytesPerRow)
            for x in 0..<width {
                let p = row.advanced(by: x * components * 2).assumingMemoryBound(to: UInt16.self)
                let v = bigEndian ? UInt16(bigEndian: p.pointee) : p.pointee
                codes[y * width + x] = v
                if v > peakCode { peakCode = v }
            }
        }
    }
    let peakNits = pqToNits(Double(peakCode) / 65535)
    let headroom = peakNits / sdrWhite
    if headroom < 1.05 {
        throw Failure(description: String(format: "peak %.0f nits is not above SDR white — the pixels are not HDR", peakNits))
    }

    if let preview {
        // Tone-mapped so `gain` lands on white: geometry only, no glow.
        let scale = 2
        var bytes = [UInt8](repeating: 0, count: width * scale * height * scale)
        for y in 0..<height * scale {
            for x in 0..<width * scale {
                let code = Double(codes[(y / scale) * width + x / scale]) / 65535
                let linear = pqToNits(code) / sdrWhite / gain
                bytes[y * width * scale + x] = UInt8(max(0, min(255, pow(linear, 1 / 2.2) * 255)))
            }
        }
        let ctx = CGContext(data: &bytes, width: width * scale, height: height * scale, bitsPerComponent: 8,
                            bytesPerRow: width * scale, space: CGColorSpaceCreateDeviceGray(),
                            bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        let out = preview.appendingPathComponent(file.deletingPathExtension().lastPathComponent + ".png")
        let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        CGImageDestinationFinalize(dest)
    }

    let bytes = (try? Data(contentsOf: file).count) ?? 0
    return String(format: "%dx%d  10-bit PQ  peak %.0f nits (%.2fx SDR)  %d B", width, height, peakNits, headroom, bytes)
}

var failures = 0
var checked = 0
let sets = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
for set in sets.filter({ $0.hasDirectoryPath }).sorted(by: { $0.path < $1.path }) {
    let manifestURL = set.appendingPathComponent("manifest.json")
    guard let manifestData = try? Data(contentsOf: manifestURL),
          let manifest = try? JSONSerialization.jsonObject(with: manifestData) as? [String: Any],
          let plates = manifest["plates"] as? [String: [String: Any]]
    else { print("\(set.lastPathComponent): no manifest.json"); failures += 1; continue }
    let gain = manifest["gain"] as? Double ?? 2
    print("\(set.lastPathComponent)  (\(plates.count) plates, gain \(gain)x)")
    let preview: URL? = previewDir.isEmpty ? nil : URL(fileURLWithPath: previewDir).appendingPathComponent(set.lastPathComponent)
    if let preview { try? FileManager.default.createDirectory(at: preview, withIntermediateDirectories: true) }
    for key in plates.keys.sorted() {
        guard let file = plates[key]?["file"] as? String else { continue }
        let url = set.appendingPathComponent(file)
        checked += 1
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("  \(file)  MISSING"); failures += 1; continue
        }
        do {
            print("  \(file)  \(try check(url, gain: gain, preview: preview))")
        } catch {
            print("  \(file)  FAIL: \(error)"); failures += 1
        }
    }
}
print(failures == 0 ? "\n\(checked) plates verified with libavif \(run(avifdec, ["--version"]).output.split(separator: "\n").first ?? "")"
                    : "\n\(failures) of \(checked) plates FAILED")
exit(failures == 0 ? 0 : 1)
