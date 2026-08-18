import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import ImageIO

/// Renders the HDR slot glow as gain-map JPEG data.
///
/// Why an image and not a colour: plain SwiftUI and UIKit colours never get
/// extended dynamic range headroom. Feeding a `Color` a component above 1.0
/// does nothing outside a Metal context. The channel that does work, and is
/// what makes HDR photos look brighter than white in Photos, is a gain-map
/// image decoded through the normal image pipeline. So the glow is literally a
/// small photo of a glowing capsule, generated at runtime.
///
/// Why runtime and not a bundled asset: asset catalogues have had unreliable
/// support for importing gain-map images, and a bundled sprite would have to be
/// stretched to fit each slot size. Encoding on demand sidesteps both, costs a
/// few milliseconds, and is cached per (size, colour).
///
/// This type is pure: same inputs, same bytes, no shared state, no UIKit. That
/// is what lets the tests assert the gain map exists rather than trusting it.
struct GlowRenderer: Sendable {
    /// How many times brighter than SDR white the glow peaks at. Actual on-screen
    /// intensity is not ours to decide: it depends on ambient light, display
    /// brightness, thermal state and Low Power Mode. This is a ceiling the system
    /// tone-maps down from, not a promise.
    var peakHeadroom: CGFloat = 6.0

    /// Brightness at the shape's edge relative to its centre, which is what
    /// makes the slot read as lit from within rather than as a flat bright chip.
    var edgeFalloff: CGFloat = 0.62

    /// How dim the base image is relative to the accent colour.
    ///
    /// This is what a screen with no headroom shows, and it is deliberately
    /// darker than a completed slot: without it, open and filled render as the
    /// same solid capsule on a non-EDR screen and the row stops being readable.
    /// On an EDR screen it also widens the gap the gain map has to climb, which
    /// makes the glow read as lit rather than merely bright.
    var sdrDimming: CGFloat = 0.5

    /// JPEG quality for the base image. The glow is a soft gradient, so this
    /// buys nothing above ~0.9 and costs encode time.
    var compressionQuality: CGFloat = 0.9

    enum RenderError: Error, Equatable {
        case emptySize
        case maskFailed
        case filterFailed
        case encodeFailed
    }

    /// Gain-map JPEG bytes for one slot.
    ///
    /// - Parameters:
    ///   - pixelSize: size in pixels, i.e. points multiplied by the display scale.
    ///   - color: the accent's sRGB components.
    func imageData(pixelSize: CGSize, color: (red: CGFloat, green: CGFloat, blue: CGFloat)) throws -> Data {
        let width = Int(pixelSize.width.rounded())
        let height = Int(pixelSize.height.rounded())
        guard width > 0, height > 0 else { throw RenderError.emptySize }

        let mask = try capsuleMask(width: width, height: height)
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        let base = CIImage(cgImage: mask)

        // The base image is a dimmed accent colour. This is what a device
        // without EDR headroom shows: a dim slot next to solid completed ones,
        // which is why graceful degradation needs no special-case code.
        let sdr = try tint(base, color: color, gain: sdrDimming, bounds: bounds)

        // Core Image infers the gain map's headroom from the brightest pixel of
        // the HDR image. Scaling by the largest colour component first means the
        // brightest channel lands exactly on `peakHeadroom` rather than on
        // `peakHeadroom * 0.85`, so the requested headroom is what gets encoded.
        let brightestComponent = max(color.red, max(color.green, color.blue))
        guard brightestComponent > 0 else { throw RenderError.filterFailed }
        let hdrGain = peakHeadroom / brightestComponent
        let hdr = try tint(base, color: color, gain: hdrGain, bounds: bounds)

        let context = CIContext(options: [
            .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB) as Any
        ])
        guard let outputSpace = CGColorSpace(name: CGColorSpace.displayP3) else {
            throw RenderError.encodeFailed
        }

        // Core Image derives the gain map from the ratio of the HDR image to the
        // SDR one and writes it as an ISO gain map auxiliary image.
        let options: [CIImageRepresentationOption: Any] = [
            .hdrImage: hdr,
            CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String):
                compressionQuality
        ]
        guard let data = context.jpegRepresentation(of: sdr, colorSpace: outputSpace, options: options)
        else { throw RenderError.encodeFailed }

        return data
    }

    /// A greyscale capsule with a radial falloff, on black.
    ///
    /// Black, not transparent, and deliberately: JPEG carries no alpha, and
    /// compositing an HDR layer with a blend mode risks the whole group being
    /// tone-mapped back to SDR. The app background is pure black, so an opaque
    /// tile is indistinguishable from a transparent one and nothing has to blend.
    private func capsuleMask(width: Int, height: Int) throws -> CGImage {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: space,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              )
        else { throw RenderError.maskFailed }

        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        let radius = min(rect.width, rect.height) / 2
        let capsule = CGPath(
            roundedRect: rect,
            cornerWidth: radius,
            cornerHeight: radius,
            transform: nil
        )

        context.saveGState()
        context.addPath(capsule)
        context.clip()
        guard let gradient = CGGradient(
            colorsSpace: space,
            colors: [
                CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
                CGColor(srgbRed: edgeFalloff, green: edgeFalloff, blue: edgeFalloff, alpha: 1)
            ] as CFArray,
            locations: [0, 1]
        ) else {
            context.restoreGState()
            throw RenderError.maskFailed
        }
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        context.drawRadialGradient(
            gradient,
            startCenter: centre,
            startRadius: 0,
            endCenter: centre,
            endRadius: max(rect.width, rect.height) / 2,
            options: [.drawsAfterEndLocation]
        )
        context.restoreGState()

        guard let image = context.makeImage() else { throw RenderError.maskFailed }
        return image
    }

    /// Multiplies the greyscale mask by the accent colour and a gain.
    private func tint(
        _ image: CIImage,
        color: (red: CGFloat, green: CGFloat, blue: CGFloat),
        gain: CGFloat,
        bounds: CGRect
    ) throws -> CIImage {
        let filter = CIFilter.colorMatrix()
        filter.inputImage = image
        // The mask is grey, so its red channel drives all three outputs.
        filter.rVector = CIVector(x: color.red * gain, y: 0, z: 0, w: 0)
        filter.gVector = CIVector(x: color.green * gain, y: 0, z: 0, w: 0)
        filter.bVector = CIVector(x: color.blue * gain, y: 0, z: 0, w: 0)
        filter.aVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        filter.biasVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        guard let output = filter.outputImage else { throw RenderError.filterFailed }
        // A non-zero bias vector applies everywhere, which gives the output an
        // infinite extent. Encoding an infinite image fails silently by
        // returning nil, so crop back to the mask before anyone tries.
        return output.cropped(to: bounds)
    }
}
