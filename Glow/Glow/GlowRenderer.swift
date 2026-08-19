import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import ImageIO

/// Renders the lit slot as an HDR image.
///
/// Why an image and not a colour: plain SwiftUI and UIKit colours never get
/// extended dynamic range headroom. Feeding a `Color` a component above 1.0
/// does nothing outside a Metal context, and SwiftUI has no HDR colour API. The
/// channel that does work is an HDR image decoded through the normal image
/// pipeline, so the lit slot is a small picture of a bright rectangle.
///
/// Why PQ and not a gain map. A gain map describes an SDR image plus "here is
/// how much brighter it could be"; PQ is a transfer function with room above
/// SDR white built in. Measured on an iPhone 14 Pro, every gain-map encoding
/// this renderer could produce came back from `UIImage.isHighDynamicRange` as
/// **false**, while both PQ encodings came back **true**. See docs/glow.md.
///
/// The output is a flat, uniform tile. It carries no shape and no gradient: the
/// slot's shape comes from clipping it, and the halo around the slot is drawn
/// by the view as an ordinary shadow. That means one tile serves every slot at
/// every size, so the whole app renders one image and reuses it.
struct GlowRenderer: Sendable {
    /// How many times brighter than SDR white the glow peaks at.
    ///
    /// In PQ this lands on an absolute luminance: reference white sits at 1.0,
    /// so 6.0 asks for roughly six times that. What the display actually shows
    /// depends on ambient light, display brightness, thermal state and Low
    /// Power Mode. This is a ceiling the system tone-maps down from.
    var peakHeadroom: CGFloat = 6.0

    /// Edge length of the rendered tile. It is uniform, so this only has to be
    /// large enough to survive resampling, not large enough to fill a slot.
    var tileSize = 16

    /// Rec. 2100 PQ, which is what the technique this app is built on calls for.
    static let colorSpace = CGColorSpace(name: CGColorSpace.itur_2100_PQ)

    /// Below this peak the tile is encoded as ordinary SDR instead.
    ///
    /// PQ declares headroom as a property of the container, not of the pixels
    /// in it: encoding a 1x image into PQ still produced a file reporting
    /// nearly 5x, so the "off" end of the slider would have gone on glowing.
    /// Switching to Display P3 makes the slot a plain bright capsule, which is
    /// what off is supposed to mean. Found by a test, not by looking.
    static let sdrThreshold: CGFloat = 1.05
    static let sdrColorSpace = CGColorSpace(name: CGColorSpace.displayP3)

    /// Core Image works in extended linear, where values above 1.0 are the
    /// point rather than an overflow to be clamped.
    static let workingSpace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)

    enum RenderError: Error, Equatable {
        case emptySize
        case maskFailed
        case filterFailed
        case encodeFailed
    }

    /// HDR image bytes for a lit slot, as 10-bit HEIF.
    func imageData(color: (red: CGFloat, green: CGFloat, blue: CGFloat)) throws -> Data {
        guard tileSize > 0 else { throw RenderError.emptySize }

        let bounds = CGRect(x: 0, y: 0, width: tileSize, height: tileSize)
        let white = try whiteTile(side: tileSize)

        // Scaling by the largest colour component first means the brightest
        // channel lands exactly on `peakHeadroom`, rather than on
        // `peakHeadroom * 0.85` for a colour whose brightest channel is 0.85.
        let brightest = max(color.red, max(color.green, color.blue))
        guard brightest > 0 else { throw RenderError.filterFailed }
        let lit = try tint(
            CIImage(cgImage: white),
            color: color,
            gain: peakHeadroom / brightest,
            bounds: bounds
        )

        let isOff = peakHeadroom <= Self.sdrThreshold
        let context = CIContext(options: [.workingColorSpace: Self.workingSpace as Any])
        guard let space = isOff ? Self.sdrColorSpace : Self.colorSpace else {
            throw RenderError.encodeFailed
        }

        // 10 bits per channel. Note this drops alpha: measured on device, an
        // encode from a bitmap with a transparent surround is byte-identical to
        // one from an opaque bitmap. The tile is opaque whatever it is drawn
        // from, which is why the view clips it rather than relying on it.
        return try context.heif10Representation(of: lit, colorSpace: space, options: [:])
    }

    private func whiteTile(side: Int) throws -> CGImage {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: space,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              )
        else { throw RenderError.maskFailed }

        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        guard let image = context.makeImage() else { throw RenderError.maskFailed }
        return image
    }

    /// Multiplies the white tile by the colour and a gain.
    private func tint(
        _ image: CIImage,
        color: (red: CGFloat, green: CGFloat, blue: CGFloat),
        gain: CGFloat,
        bounds: CGRect
    ) throws -> CIImage {
        let filter = CIFilter.colorMatrix()
        filter.inputImage = image
        filter.rVector = CIVector(x: color.red * gain, y: 0, z: 0, w: 0)
        filter.gVector = CIVector(x: color.green * gain, y: 0, z: 0, w: 0)
        filter.bVector = CIVector(x: color.blue * gain, y: 0, z: 0, w: 0)
        filter.aVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        filter.biasVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        guard let output = filter.outputImage else { throw RenderError.filterFailed }
        // A non-zero bias vector applies everywhere, which gives the output an
        // infinite extent. Encoding an infinite image fails by returning nil
        // with no error, so crop before anyone tries.
        return output.cropped(to: bounds)
    }
}
