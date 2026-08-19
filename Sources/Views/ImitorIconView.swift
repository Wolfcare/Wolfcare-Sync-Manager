//
//  ImitorIconView.swift
//
//  Native SwiftUI reproduction of `imitor_icon_dark 9 and final.svg`
//  for macOS, with the "Squares" layer rotating 360° clockwise every
//  5 seconds. Every other layer is reproduced exactly and stays static.
//
//  Geometry is authored in the SVG's native 1024 × 1024 coordinate space
//  and scaled to whatever size the view is given, so it stays crisp at
//  any resolution — menu-bar size through 1024pt.
//
//  Requires macOS 12+ (TimelineView).
//

import SwiftUI

// MARK: - Rotation model

/// Drives the Squares rotation from wall-clock time.
///
/// The angle is derived from elapsed time rather than from a
/// `.repeatForever` animation. That matters for start/stop control:
/// `.repeatForever` cannot be halted mid-cycle without snapping, and
/// repeated pause/resume drifts. Deriving from a timestamp means pause
/// freezes exactly where it was and resume continues from that angle.
@MainActor
public final class SquaresRotation: ObservableObject {

    /// Whether the trail is currently turning.
    @Published public private(set) var isRunning = false

    /// Degrees travelled before the current run began.
    @Published public private(set) var accumulatedDegrees: Double = 0

    /// Timestamp the current run began; `nil` while stopped.
    private var runStart: Date?

    /// Seconds for one full 360° revolution.
    public let secondsPerRevolution: Double

    /// When stopping, return to 0° instead of freezing in place.
    public var resetsOnStop: Bool

    public init(secondsPerRevolution: Double = 5, resetsOnStop: Bool = true) {
        self.secondsPerRevolution = secondsPerRevolution
        self.resetsOnStop = resetsOnStop
    }

    /// Current clockwise rotation, in degrees, at the given instant.
    public func degrees(at date: Date) -> Double {
        guard let runStart else { return accumulatedDegrees }
        let travelled = date.timeIntervalSince(runStart) / secondsPerRevolution * 360
        return (accumulatedDegrees + travelled).truncatingRemainder(dividingBy: 360)
    }

    /// Start turning, or resume from a paused angle.
    public func start() {
        guard !isRunning else { return }
        runStart = Date()
        isRunning = true
    }

    /// Freeze in place; a later `start()` picks up from here.
    public func pause() {
        guard isRunning else { return }
        accumulatedDegrees = degrees(at: Date())
        runStart = nil
        isRunning = false
    }

    /// Halt. Returns to 0° when `resetsOnStop` is true.
    public func stop() {
        accumulatedDegrees = resetsOnStop ? 0 : degrees(at: Date())
        runStart = nil
        isRunning = false
    }
}

// MARK: - Design-space plumbing

/// The SVG's authoring canvas. All coordinates below are in these units.
private let designSize: CGFloat = 1024
private let designCenter = CGPoint(x: 512, y: 512)

private extension Color {
    /// `Color(hex: 0xEBEBEB)`
    init(hex: UInt32) {
        self.init(.sRGB,
                  red:   Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8)  & 0xFF) / 255,
                  blue:  Double( hex        & 0xFF) / 255)
    }
}

private func unit(_ rect: CGRect) -> CGFloat {
    min(rect.width, rect.height) / designSize
}

private func scaled(_ p: CGPoint, in rect: CGRect) -> CGPoint {
    let s = unit(rect)
    return CGPoint(x: p.x * s, y: p.y * s)
}

/// A circle expressed in design-space coordinates.
private struct DesignCircle: Shape {
    var center: CGPoint = designCenter
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let c = scaled(center, in: rect)
        let r = radius * unit(rect)
        return Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    }
}

/// An ellipse expressed in design-space coordinates.
private struct DesignEllipse: Shape {
    var center: CGPoint
    var rx: CGFloat
    var ry: CGFloat

    func path(in rect: CGRect) -> Path {
        let c = scaled(center, in: rect)
        let a = rx * unit(rect), b = ry * unit(rect)
        return Path(ellipseIn: CGRect(x: c.x - a, y: c.y - b, width: a * 2, height: b * 2))
    }
}

/// A straight segment expressed in design-space coordinates.
private struct DesignLine: Shape {
    var from: CGPoint
    var to: CGPoint

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: scaled(from, in: rect))
        p.addLine(to: scaled(to, in: rect))
        return p
    }
}

/// The L-shaped mechanism plate — the SVG's relative path commands
/// converted to absolute design-space coordinates.
private struct MechanismShape: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            scaled(CGPoint(x: x, y: y), in: rect)
        }
        var path = Path()
        path.move(to: p(135.25, 709.62))
        path.addLine(to: p(192.25, 709.62))
        path.addCurve(to: p(206.25, 723.97),
                      control1: p(199.98, 709.62), control2: p(206.25, 716.04))
        path.addLine(to: p(206.25, 765.99))
        path.addCurve(to: p(261.25, 822.36),
                      control1: p(206.25, 797.12), control2: p(230.87, 822.36))
        path.addLine(to: p(297.25, 822.36))
        path.addCurve(to: p(311.25, 836.71),
                      control1: p(304.98, 822.36), control2: p(311.25, 828.78))
        path.addLine(to: p(311.25, 879.75))
        path.addCurve(to: p(297.25, 894.10),
                      control1: p(311.25, 887.67), control2: p(304.98, 894.10))
        path.addLine(to: p(135.25, 894.10))
        path.addCurve(to: p(121.25, 879.75),
                      control1: p(127.52, 894.10), control2: p(121.25, 887.68))
        path.addLine(to: p(121.25, 723.97))
        path.addCurve(to: p(135.25, 709.62),
                      control1: p(121.25, 716.05), control2: p(127.52, 709.62))
        path.closeSubpath()
        return path
    }
}

// MARK: - Squares (the animated layer)

/// The six tick marks forming the motion trail — the SVG's `Squares` group.
///
/// Exposed on its own so it can also be composited over an exported
/// static asset instead of the native base below.
public struct SquaresLayer: View {

    private struct Tick {
        let a: CGPoint, b: CGPoint
        let color: Color
        let opacity: Double
    }

    /// Listed in the SVG's own draw order (faintest first).
    private static let ticks: [Tick] = [
        Tick(a: CGPoint(x: 792.58, y: 639.03), b: CGPoint(x: 857.59, y: 668.15),
             color: Color(hex: 0xDBDBDC), opacity: 0.03),
        Tick(a: CGPoint(x: 746.89, y: 314.49), b: CGPoint(x: 801.33, y: 268.55),
             color: Color(hex: 0xEBEBEB), opacity: 1.00),
        Tick(a: CGPoint(x: 785.19, y: 371.85), b: CGPoint(x: 848.48, y: 339.17),
             color: Color(hex: 0xAEB0B2), opacity: 1.00),
        Tick(a: CGPoint(x: 809.76, y: 436.30), b: CGPoint(x: 878.73, y: 418.53),
             color: Color(hex: 0x7E7F81), opacity: 1.00),
        Tick(a: CGPoint(x: 819.38, y: 504.59), b: CGPoint(x: 890.57, y: 502.62),
             color: Color(hex: 0x535456), opacity: 0.89),
        Tick(a: CGPoint(x: 813.55, y: 573.32), b: CGPoint(x: 883.40, y: 587.25),
             color: Color(hex: 0x686A6C), opacity: 0.46),
    ]

    private static let tickWidth: CGFloat = 51.49

    public init() {}

    public var body: some View {
        GeometryReader { geo in
            let rect = CGRect(origin: .zero, size: geo.size)
            ZStack {
                ForEach(Array(Self.ticks.enumerated()), id: \.offset) { _, t in
                    DesignLine(from: t.a, to: t.b)
                        .stroke(t.color,
                                style: StrokeStyle(lineWidth: Self.tickWidth * unit(rect),
                                                   lineCap: .butt))
                        .opacity(t.opacity)
                }
            }
        }
    }
}

// MARK: - Static base

/// Every layer of the icon except `Squares`.
public struct IconBaseLayer: View {

    public init() {}

    /// The six inner dots, hex-arranged at radius ~29.4 from centre.
    private static let innerDots: [CGPoint] = [
        CGPoint(x: 497.46, y: 537.59),
        CGPoint(x: 482.57, y: 512.21),
        CGPoint(x: 497.12, y: 486.62),
        CGPoint(x: 526.55, y: 486.42),
        CGPoint(x: 541.43, y: 511.80),
        CGPoint(x: 526.89, y: 537.39),
    ]

    /// Mechanism screw positions.
    private static let screws: [CGPoint] = [
        CGPoint(x: 164.50, y: 749.79),
        CGPoint(x: 270.71, y: 856.34),
        CGPoint(x: 164.50, y: 853.25),
    ]

    public var body: some View {
        GeometryReader { geo in
            let rect = CGRect(origin: .zero, size: geo.size)
            let s = unit(rect)

            ZStack {
                // Squircle plate
                RoundedRectangle(cornerRadius: 229.38 * s, style: .continuous)
                    .fill(Color(hex: 0x1A1A1A))

                // Outer hairline ring
                DesignCircle(radius: 417.18)
                    .stroke(Color(hex: 0xEBEBEB), lineWidth: 6.25 * s)

                // Hub ring and platter ring
                DesignCircle(radius: 127.58)
                    .stroke(Color(hex: 0x969696), lineWidth: 45.89 * s)
                DesignCircle(radius: 268.66)
                    .stroke(Color(hex: 0x969696), lineWidth: 45.89 * s)

                // Translucent spindle disc
                ZStack {
                    DesignCircle(radius: 69.08).fill(.white)
                    DesignCircle(radius: 69.08)
                        .stroke(Color(hex: 0x141414), lineWidth: 7 * s)
                }
                .opacity(0.43)

                // Inner dot cluster
                ForEach(Array(Self.innerDots.enumerated()), id: \.offset) { _, c in
                    DesignCircle(center: c, radius: 0.49)
                        .fill(Color(hex: 0xEBEBEB))
                        .overlay(
                            DesignCircle(center: c, radius: 0.49)
                                .stroke(Color(hex: 0x231F20), lineWidth: 7 * s)
                        )
                }

                // Actuator arm rails
                Group {
                    DesignLine(from: CGPoint(x: 405.65, y: 600.86),
                               to:   CGPoint(x: 270.01, y: 723.20))
                        .stroke(Color(hex: 0x5A5F66), lineWidth: 7 * s)
                    DesignLine(from: CGPoint(x: 415.75, y: 616.20),
                               to:   CGPoint(x: 299.75, y: 752.12))
                        .stroke(Color(hex: 0x5A5F66), lineWidth: 7 * s)
                }

                // Voice-coil pivot
                DesignCircle(center: CGPoint(x: 263.47, y: 756.97), radius: 36)
                    .fill(Color(hex: 0x231F20))
                DesignCircle(center: CGPoint(x: 263.47, y: 756.97), radius: 36)
                    .stroke(Color(hex: 0x7E7F81), lineWidth: 7 * s)

                // Read/write head
                DesignCircle(center: CGPoint(x: 420.83, y: 600.35), radius: 16.24)
                    .fill(Color(hex: 0x231F20))
                DesignCircle(center: CGPoint(x: 420.83, y: 600.35), radius: 16.24)
                    .stroke(Color(hex: 0x686A6C), lineWidth: 7 * s)

                // Centre spindle
                DesignCircle(radius: 9.18)
                    .fill(Color(hex: 0x231F20))
                DesignCircle(radius: 9.18)
                    .stroke(Color(hex: 0x535456), lineWidth: 8 * s)

                // Mechanism plate
                MechanismShape().fill(Color(hex: 0x231F20))
                MechanismShape().stroke(Color(hex: 0x686A6C), lineWidth: 7 * s)

                ForEach(Array(Self.screws.enumerated()), id: \.offset) { _, c in
                    DesignEllipse(center: c, rx: 16.24, ry: 16.64)
                        .fill(Color(hex: 0x231F20))
                    DesignEllipse(center: c, rx: 16.24, ry: 16.64)
                        .stroke(Color(hex: 0x7E7F81), lineWidth: 7 * s)
                }

                // Corner rules
                Group {
                    DesignLine(from: CGPoint(x: 119.90, y: 938.81),
                               to:   CGPoint(x: 927.83, y: 933.36))
                        .stroke(.white, lineWidth: 5 * s)
                    DesignLine(from: CGPoint(x: 929.58, y: 662.71),
                               to:   CGPoint(x: 929.58, y: 935.86))
                        .stroke(.white, lineWidth: 5 * s)
                }
            }
            .frame(width: rect.width, height: rect.height)
        }
    }
}

// MARK: - Composed icon

/// The complete icon with `Squares` rotating clockwise while running.
public struct ImitorIconView: View {

    @ObservedObject private var rotation: SquaresRotation

    public init(rotation: SquaresRotation) {
        self.rotation = rotation
    }

    public var body: some View {
        ZStack {
            IconBaseLayer()

            // `paused: true` schedules no frames at all, so a still icon
            // costs nothing — it is not ticking invisibly in the background.
            TimelineView(.animation(paused: !rotation.isRunning)) { context in
                SquaresLayer()
                    .rotationEffect(.degrees(rotation.degrees(at: context.date)),
                                    anchor: .center)
            }
            .animation(rotation.isRunning ? nil : .easeOut(duration: 0.35),
                       value: rotation.accumulatedDegrees)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// Convenience wrapper when you just want it spinning off a `Bool`
/// and don't need pause/resume semantics.
public struct ImitorIcon: View {

    private let isAnimating: Bool
    @StateObject private var rotation: SquaresRotation

    public init(isAnimating: Bool, secondsPerRevolution: Double = 5) {
        self.isAnimating = isAnimating
        _rotation = StateObject(
            wrappedValue: SquaresRotation(secondsPerRevolution: secondsPerRevolution)
        )
    }

    public var body: some View {
        ImitorIconView(rotation: rotation)
            .onAppear { sync() }
            .onChange(of: isAnimating) { _ in sync() }
    }

    private func sync() {
        isAnimating ? rotation.start() : rotation.stop()
    }
}

// MARK: - Usage
/*
 Simplest form — drive it from a Bool:

     ImitorIcon(isAnimating: syncEngine.isRunning)
         .frame(width: 128, height: 128)

 Full control, including pause/resume that keeps its place:

     @StateObject private var rotation = SquaresRotation(secondsPerRevolution: 5)

     ImitorIconView(rotation: rotation)
         .frame(width: 128, height: 128)

     rotation.start()    // begin, or resume from the paused angle
     rotation.pause()    // freeze in place
     rotation.stop()     // halt (returns to 0° unless resetsOnStop == false)

 Wire it to a sync task:

     Task {
         rotation.start()
         defer { rotation.stop() }     // also runs on throw or cancel
         try await syncEngine.run()
     }

 As a menu-bar extra:

     MenuBarExtra {
         …
     } label: {
         ImitorIcon(isAnimating: engine.isRunning)
     }
     .menuBarExtraStyle(.window)
*/

// MARK: - Preview

#Preview("Imitor icon") {
    struct Harness: View {
        @StateObject private var rotation = SquaresRotation(secondsPerRevolution: 5)

        var body: some View {
            VStack(spacing: 28) {
                ImitorIconView(rotation: rotation)
                    .frame(width: 300, height: 300)

                HStack(spacing: 24) {
                    ImitorIconView(rotation: rotation).frame(width: 64, height: 64)
                    ImitorIconView(rotation: rotation).frame(width: 32, height: 32)
                    ImitorIconView(rotation: rotation).frame(width: 18, height: 18)
                }

                Text(rotation.isRunning ? "running" : "stopped")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Button("Start") { rotation.start() }
                    Button("Pause") { rotation.pause() }
                    Button("Stop")  { rotation.stop() }
                }
                .buttonStyle(.bordered)
            }
            .padding(40)
            .frame(width: 460)
        }
    }
    return Harness()
}
