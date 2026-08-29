import AppKit
import Combine

/// Renders the menu bar icon using plain AppKit/Core Graphics — deliberately
/// NOT SwiftUI's `ImageRenderer`.
///
/// The previous version used `ImageRenderer` to rasterize `ImitorIconView`
/// (which relies on `GeometryReader` + several custom `Shape`s) into a bitmap,
/// run synchronously in `App.init()` — i.e. the very first SwiftUI rendering
/// work the app does, before any window exists. That reproducibly crashed
/// with a SwiftUI/AttributeGraph assertion failure at launch on at least one
/// real Mac (every launch, regardless of task data, Low Power Mode on or
/// off). `ImageRenderer` + `GeometryReader`-based content rendered off-screen
/// is a known-fragile SwiftUI path on some GPU/driver combinations, so the
/// menu bar icon now stays entirely outside the SwiftUI rendering pipeline.
///
/// Only the "Squares" tick marks rotate — matching `ImitorIconView`, where
/// `.rotationEffect` is applied to `SquaresLayer()` alone, never to
/// `IconBaseLayer()`. The static `MenuBarLogo` asset stands in for the base
/// (drawn once, never rotated); the ticks are drawn separately, rotated,
/// using the same design-space coordinates as `SquaresLayer`.
@MainActor
final class MenuBarIconRenderer: ObservableObject {
    @Published private(set) var image: NSImage

    private let rotation: SquaresRotation
    private var timer: Timer?
    private var cancellable: AnyCancellable?
    private static let pointSize: CGFloat = 24
    private static let designSize: CGFloat = 1024
    private static let designCenter = CGPoint(x: 512, y: 512)

    private struct Tick {
        let a: CGPoint, b: CGPoint
        let color: NSColor
        let opacity: CGFloat
    }

    /// Same coordinates, colors, and draw order as `SquaresLayer.ticks`.
    private static let ticks: [Tick] = [
        Tick(a: CGPoint(x: 792.58, y: 639.03), b: CGPoint(x: 857.59, y: 668.15),
             color: NSColor(hex: 0xDBDBDC), opacity: 0.03),
        Tick(a: CGPoint(x: 746.89, y: 314.49), b: CGPoint(x: 801.33, y: 268.55),
             color: NSColor(hex: 0xEBEBEB), opacity: 1.00),
        Tick(a: CGPoint(x: 785.19, y: 371.85), b: CGPoint(x: 848.48, y: 339.17),
             color: NSColor(hex: 0xAEB0B2), opacity: 1.00),
        Tick(a: CGPoint(x: 809.76, y: 436.30), b: CGPoint(x: 878.73, y: 418.53),
             color: NSColor(hex: 0x7E7F81), opacity: 1.00),
        Tick(a: CGPoint(x: 819.38, y: 504.59), b: CGPoint(x: 890.57, y: 502.62),
             color: NSColor(hex: 0x535456), opacity: 0.89),
        Tick(a: CGPoint(x: 813.55, y: 573.32), b: CGPoint(x: 883.40, y: 587.25),
             color: NSColor(hex: 0x686A6C), opacity: 0.46),
    ]
    private static let tickWidth: CGFloat = 51.49

    private static let baseImage: NSImage = {
        let image = NSImage(named: "MenuBarLogo") ?? NSImage(size: NSSize(width: pointSize, height: pointSize))
        image.size = NSSize(width: pointSize, height: pointSize)
        return image
    }()

    init(rotation: SquaresRotation) {
        self.rotation = rotation
        self.image = Self.render(rotation: rotation)
        cancellable = rotation.$isRunning
            .sink { [weak self] isRunning in
                self?.setAnimating(isRunning)
            }
    }

    deinit {
        timer?.invalidate()
    }

    private func setAnimating(_ animating: Bool) {
        timer?.invalidate()
        timer = nil
        guard animating else {
            image = Self.render(rotation: rotation)
            return
        }
        let ticker = Timer(timeInterval: 1.0 / 24.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.image = Self.render(rotation: self.rotation) }
        }
        RunLoop.main.add(ticker, forMode: .common)
        timer = ticker
    }

    private static func render(rotation: SquaresRotation) -> NSImage {
        let degrees = rotation.degrees(at: Date())
        let size = NSSize(width: pointSize, height: pointSize)
        let scale = pointSize / designSize
        let center = NSPoint(x: size.width / 2, y: size.height / 2)
        let output = NSImage(size: size)

        output.lockFocus()
        let context = NSGraphicsContext.current

        // Static base — never rotated.
        baseImage.draw(in: NSRect(origin: .zero, size: size))

        // Rotating "Squares" ticks, drawn on top.
        context?.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: center.x, yBy: center.y)
        // Negative: this Y-up context is the standard math convention
        // (positive = counter-clockwise), but the design's "clockwise"
        // rotation was authored for SwiftUI's Y-down convention.
        transform.rotate(byDegrees: -degrees)
        transform.translateX(by: -center.x, yBy: -center.y)
        transform.concat()

        for tick in ticks {
            let path = NSBezierPath()
            path.lineWidth = max(0.5, tickWidth * scale)
            path.lineCapStyle = .butt
            path.move(to: NSPoint(x: tick.a.x * scale, y: (designSize - tick.a.y) * scale))
            path.line(to: NSPoint(x: tick.b.x * scale, y: (designSize - tick.b.y) * scale))
            tick.color.withAlphaComponent(tick.opacity).setStroke()
            path.stroke()
        }
        context?.restoreGraphicsState()

        output.unlockFocus()
        output.isTemplate = false
        return output
    }
}

private extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}
