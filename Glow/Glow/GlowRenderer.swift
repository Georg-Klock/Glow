import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import ImageIO

/// Renders the slot glow as an HDR image.
///
/// Why an image and not a colour: plain SwiftUI and UIKit colours never get
/// extended dynamic range headroom. Feeding a `Color` a component above 1.0
/// does nothing outside a Metal context, and SwiftUI has no HDR colour API. The
/// channel that does work is an HDR image decoded through the normal image
/// pipeline, so the glow is literally a small photo of a glowing capsule,
/// generated at runtime and cached per size and colour.
///
/// Why PQ and not a gain map. A gain map describes an SDR image plus "here is
/// how much brighter it could be"; PQ is a transfer function with room above
/// SDR white built in, so the bright pixels are simply in the file. Both are
/// legitimate ways to store HDR, and only one of them works here: measured on
/// an iPhone 14 Pro, every gain-map encoding this renderer could produce came
/// back from `UIImage.isHighDynamicRange` as **false**, while both PQ encodings
/// came back **true**. A gain map that the image pipeline declines to treat as
/// HDR is an ordinary picture of a dim capsule. See docs/glow.md.
struct GlowRenderer: Sendable {
    /// How many times brighter than SDR white the glow peaks at.
    ///
    /// In PQ this lands on an absolute luminance: reference white sits at 1.0,
    /// so 6.0 asks for roughly six times that. What the display actually shows
    /// is not ours to decide, because it depends on ambient light, display
    /// brightness, thermal state and Low Power Mode. This is a ceiling the
    /// system tone-maps down from, not a promise.
    var peakHeadroom: CGFloat = 6.0

    /// Brightness at the shape's edge relative to its centre, which is what
    /// makes the slot read as lit from within rather than as a flat bright chip.
    var edgeFalloff: CGFloat = 0.62

    /// Colour space for the encoded image.
    ///
    /// Rec. 2100 PQ, which is what the technique this app is built on calls for.
    /// Display P3 PQ measures as HDR too and is the narrower gamut of the two.
    static let colorSpace = CGColorSpace(name: CGColorSpace.itur_2100_PQ)

    /// Core Image works in extended linear, where values above 1.0 are exactly
    /// the point rather than an overflow to be clamped.
    static let workingSpace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)

    enum RenderError: Error, Equatable {
        case emptySize
        case maskFailed
        case filterFailed
        case encodeFailed
    }

    /// HDR image bytes for one slot, as 10-bit HEIF.
    ///
    /// - Parameters:
    ///   - pixelSize: size in pixels, i.e. points multiplied by the display scale.
    ///   - color: the accent's sRGB components.
    func imageData(
        pixelSize: CGSize,
        color: (red: CGFloat, green: CGFloat, blue: CGFloat)
    ) throws -> Data {
        let width = Int(pixelSize.width.rounded())
        let height = Int(pixelSize.height.rounded())
        guard width > 0, height > 0 else { throw RenderError.emptySize }

        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        let mask = CIImage(cgImage: try capsuleMask(width: width, height: height))

        // Scaling by the largest colour component first means the brightest
        // channel lands exactly on `peakHeadroom`, rather than on
        // `peakHeadroom * 0.85` for an accent whose brightest channel is 0.85.
        // Without it every accent glows a different amount, and the amount
        // depends on its hue.
        let brightest = max(color.red, max(color.green, color.blue))
        guard brightest > 0 else { throw RenderError.filterFailed }
        let glow = try tint(mask, color: color, gain: peakHeadroom / brightest, bounds: bounds)

        let context = CIContext(options: [.workingColorSpace: Self.workingSpace as Any])
        guard let space = Self.colorSpace else { throw RenderError.encodeFailed }

        // 10 bits per channel: PQ across a soft gradient bands visibly at 8.
        //
        // Note that this drops alpha. Measured on device, an encode from a
        // bitmap with a transparent surround produces byte-identical output to
        // one from an opaque bitmap, so the tile is opaque whatever it is drawn
        // from. Callers clip it to the slot shape rather than relying on it.
        return try context.heif10Representation(of: glow, colorSpace: space, options: [:])
    }

    /// A greyscale capsule with a radial falloff, on black.
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
        context.saveGState()
        context.addPath(CGPath(
            roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil
        ))
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
        // infinite extent. Encoding an infinite image fails by returning nil
        // with no error, so crop back to the mask before anyone tries.
        return output.cropped(to: bounds)
    }
}
