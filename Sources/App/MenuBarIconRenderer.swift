import SwiftUI
import AppKit
import Combine

/// Rasterizes `ImitorIconView` into a plain `NSImage` for the menu bar.
///
/// `MenuBarExtra`'s status-item slot doesn't reliably host live SwiftUI
/// content built on `GeometryReader`/`TimelineView` — it renders fine in a
/// normal window but can come up blank in the tray. Pre-rendering frames to
/// a bitmap and handing the label a plain `Image(nsImage:)` sidesteps that
/// entirely, at the cost of driving our own animation timer.
@MainActor
final class MenuBarIconRenderer: ObservableObject {
    @Published private(set) var image: NSImage

    private let rotation: SquaresRotation
    private var timer: Timer?
    private var cancellable: AnyCancellable?
    private static let pointSize: CGFloat = 24

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
        let content = ZStack {
            IconBaseLayer()
            SquaresLayer().rotationEffect(.degrees(degrees), anchor: .center)
        }
        .frame(width: pointSize, height: pointSize)

        let renderer = ImageRenderer(content: content)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage ?? NSImage(size: NSSize(width: pointSize, height: pointSize))
        image.isTemplate = false
        return image
    }
}
