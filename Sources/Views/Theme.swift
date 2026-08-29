import SwiftUI

/// The app's visual language, pulled directly from Design/imitor_icon.svg's own
/// palette — a monochrome "brushed chrome on charcoal" look. Transport controls
/// (sync/pause/stop) read by icon shape alone, not color, so the whole interface
/// stays cohesive with the logo rather than looking like a generic system app.
enum Theme {
    static let charcoalBase = Color(hex: 0x1A1A1A)
    static let charcoalDeep = Color(hex: 0x231F20)
    static let paneBackground = Color(hex: 0x141414)

    static let dark1 = Color(hex: 0x535456)
    static let dark2 = Color(hex: 0x686A6C)
    static let dark3 = Color(hex: 0x5A5F66)

    static let gray1 = Color(hex: 0x7E7F81)
    static let gray2 = Color(hex: 0x969696)
    static let gray3 = Color(hex: 0xAEB0B2)

    static let highlight1 = Color(hex: 0xDBDBDC)
    static let highlight2 = Color(hex: 0xEBEBEB)

    // Flat, not a gradient: a LinearGradient fill here forces a custom Metal
    // shader compile the moment the app launches (these buttons render
    // unconditionally in the sidebar on every launch, regardless of task
    // data) — that triggered a reproducible SwiftUI/AttributeGraph crash on
    // at least one real Mac (M3 Pro, Low Power Mode on), within ~100ms of
    // every launch. Flat color renders through the normal path instead.
    static let chromeFill = dark2
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// A circular chrome transport button (sync/pause/stop/etc.) — differentiated
/// by icon shape, not color, matching the logo's monochrome treatment.
struct ChromeIconButton: View {
    let systemImage: String
    let size: CGFloat
    let iconScale: CGFloat
    let action: () -> Void

    init(systemImage: String, size: CGFloat = 34, iconScale: CGFloat = 0.42, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.size = size
        self.iconScale = iconScale
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * iconScale, weight: .medium))
                .foregroundStyle(Theme.highlight2)
                .frame(width: size, height: size)
                .background(Theme.chromeFill, in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.08), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// A dark pill-shaped segmented control matching the logo's chrome styling —
/// standard `Picker(.segmented)` can't be recolored on macOS, so this replaces it.
struct ChromeSegmentedControl<Tab: Hashable>: View {
    let tabs: [(Tab, String)]
    @Binding var selection: Tab

    var body: some View {
        HStack(spacing: 2) {
            ForEach(tabs, id: \.0) { tab, title in
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(selection == tab ? Theme.highlight2 : Theme.gray2)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 5)
                    .background(selection == tab ? Theme.dark2 : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .contentShape(Rectangle())
                    .onTapGesture { selection = tab }
            }
        }
        .padding(3)
        .background(Theme.charcoalDeep, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// A dark chrome progress bar — native `ProgressView` can't have its track
/// recolored on macOS, so this replaces it for the sync progress display.
struct ChromeProgressBar: View {
    let fraction: Double
    var tint: Color = Theme.highlight2

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Theme.dark1)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(tint)
                    .frame(width: geo.size.width * max(0, min(1, fraction)))
            }
        }
        .frame(height: 6)
    }
}

/// A bordered chrome button for secondary actions ("Choose Destination…", etc.)
struct ChromeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(Theme.highlight2)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Theme.dark1.opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(.white.opacity(0.08), lineWidth: 1))
    }
}

extension ButtonStyle where Self == ChromeButtonStyle {
    static var chrome: ChromeButtonStyle { ChromeButtonStyle() }
}
