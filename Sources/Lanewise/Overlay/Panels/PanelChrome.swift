import AppKit
import SwiftUI

extension OverlayWindowKind {
    var width: CGFloat {
        switch self {
        case .lanes: 360
        case .hud, .hudTab: 196
        }
    }
}

/// Root view of each overlay window.
struct OverlayHost: View {
    let window: OverlayWindowKind

    var body: some View {
        let settings = AppSettings.shared
        PanelChrome(window: window) {
            switch window {
            case .lanes: LanesPanel()
            case .hud: HUDStack(modules: [.cooldowns, .farm])
            case .hudTab: HUDStack(modules: [.gold, .build])
            }
        }
        .environment(GameMonitor.shared)
        .environment(settings)
        .environment(OverlayManager.shared)
        .environment(MetaStore.shared)
        .environment(\.overlayScale, CGFloat(settings.textScale) * OverlayScale.screenFactor)
        .environment(\.isHUD, true)
        .environment(\.colorScheme, .dark)
        // Values change every poll; nothing should animate over the game.
        .transaction { $0.animation = nil }
    }
}

/// Some of the HUD's modules stacked in one tile, with hairlines between them.
struct HUDStack: View {
    @Environment(OverlayManager.self) private var overlay
    @Environment(\.overlayScale) private var scale
    let modules: [OverlayPanelKind]

    var body: some View {
        let modules = modules.filter { overlay.visiblePanels.contains($0) }
        VStack(alignment: .leading, spacing: 10 * scale) {
            ForEach(Array(modules.enumerated()), id: \.element) { index, module in
                if index > 0 { Hairline() }
                PanelContent(kind: module)
            }
        }
    }
}

/// A module's content, shared by the HUD and the Game Plan screen.
struct PanelContent: View {
    let kind: OverlayPanelKind

    var body: some View {
        switch kind {
        case .scout: LanesPanel()
        case .cooldowns: SpellTimersPanel()
        case .gold: GoldDiffPanel()
        case .build: NextItemPanel()
        case .farm: CSPanel()
        }
    }
}

/// Flat dark tile with a slim header: the live game clock on the left and a × that hides the tile
/// until the next game. Arrange mode swaps the header for a drag handle and adds an accent ring.
struct PanelChrome<Content: View>: View {
    @Environment(OverlayManager.self) private var overlay
    @Environment(GameMonitor.self) private var monitor
    @Environment(\.overlayScale) private var scale
    let window: OverlayWindowKind
    @ViewBuilder let content: Content

    var body: some View {
        let radius = 14 * scale
        VStack(alignment: .leading, spacing: 8 * scale) {
            if window != .hudTab || overlay.isMoveMode { header }
            content
        }
        .padding(12 * scale)
        .frame(width: window.width * scale, alignment: .leading)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: radius, style: .continuous).fill(HUD.fill)
                // The Tab section follows the HUD, so only the HUD itself is dragged.
                if overlay.isMoveMode && window != .hudTab { WindowDragArea() }
            }
        }
        .overlay {
            if overlay.isMoveMode {
                RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Color.accentColor, lineWidth: 2)
            }
        }
    }

    @ViewBuilder private var header: some View {
        HStack(spacing: 6 * scale) {
            if overlay.isMoveMode {
                if window == .hudTab {
                    Text("Shows while Tab is held").sfont(10).foregroundStyle(Palette.secondaryLabel)
                } else {
                    Image(systemName: "line.3.horizontal").sfont(10).foregroundStyle(Palette.secondaryLabel)
                    Text(window.title).sfont(12, .semibold).foregroundStyle(.white)
                    Spacer(minLength: 0)
                    Text("Drag to move").sfont(10).foregroundStyle(Palette.secondaryLabel)
                }
            } else {
                headerLeading
                Spacer(minLength: 4)
                CloseButton { overlay.dismiss(window) }
            }
        }
        .frame(height: 18 * scale)
    }

    @ViewBuilder private var headerLeading: some View {
        if monitor.live != nil {
            GameClock()
        } else {
            Text("Loading screen").sfont(11, .medium).foregroundStyle(Palette.secondaryLabel)
        }
        switch window {
        case .lanes:
            if let queue = monitor.queueName {
                Text(queue).sfont(10.5).foregroundStyle(Palette.secondaryLabel).lineLimit(1)
            }
        case .hud:
            // A fixed hint (it doesn't change with Tab, so the tile never resizes).
            if AppSettings.shared.enabledPanels.contains(where: { [.gold, .build].contains($0) }) {
                Text("Tab: gold, item").sfont(10).foregroundStyle(Palette.secondaryLabel).lineLimit(1)
            }
        case .hudTab:
            EmptyView()
        }
    }
}

/// Live game clock that ticks every second between data polls.
struct GameClock: View {
    @Environment(GameMonitor.self) private var monitor

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(Format.clock(monitor.estimatedGameTime(at: context.date))).sfont(12, .semibold, rounded: true)
        }
    }
}

struct CloseButton: View {
    @Environment(\.overlayScale) private var scale
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 8 * scale, weight: .bold))
                .foregroundStyle(Palette.secondaryLabel)
                .frame(width: 18 * scale, height: 18 * scale)
                .background(Circle().fill(Color.white.opacity(0.1)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Hide until the next game")
    }
}

/// System Settings-style icon tile for a module.
struct PanelTile: View {
    let kind: OverlayPanelKind
    var size: CGFloat = 20

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
            .fill(Palette.tile(kind))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: kind.symbol)
                    .font(.system(size: size * 0.55, weight: .semibold))
                    .foregroundStyle(kind == .gold ? Color.black.opacity(0.8) : .white)
            }
    }
}

/// Drags the overlay window. Content inside a borderless panel doesn't reliably honor
/// `isMovableByWindowBackground`, so the drag is started explicitly.
struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }

    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct PanelNote: View {
    let text: String

    var body: some View {
        Text(text)
            .sfont(11)
            .foregroundStyle(Palette.secondaryLabel)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct Hairline: View {
    @Environment(\.isHUD) private var isHUD

    var body: some View {
        Rectangle().fill(isHUD ? HUD.hairline : Palette.separator).frame(height: 1)
    }
}
