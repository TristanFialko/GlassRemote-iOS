import SwiftUI

/// Phase 8: the Remote's secondary navigation keys. Pure description (unit tested): each key
/// appears once, the Apps launcher key is in the portrait cluster (landscape has a launcher card in
/// the leading column instead), and Sources is offered only while the Samsung link is enabled.
enum RemoteNavKey: String, Hashable, CaseIterable {
    case back, home, apps, search, keyboard, sources

    static func cluster(isLandscape: Bool, samsungLinked: Bool) -> [RemoteNavKey] {
        var keys: [RemoteNavKey] = isLandscape ? [.back, .home, .search, .keyboard]
                                               : [.back, .home, .apps, .search, .keyboard]
        if samsungLinked { keys.append(.sources) }
        return keys
    }

    var title: String {
        switch self {
        case .back: return "Back"
        case .home: return "Home"
        case .apps: return "Apps"
        case .search: return "Search"
        case .keyboard: return "Keyboard"
        case .sources: return "Sources"
        }
    }

    /// Phase 9 §1.1: the keys are icon-only. `title` stays the VoiceOver name, the pointer
    /// tooltip and the Large Content Viewer label.
    static let showsCaptions = false

    /// SF Symbol for the key. Home draws `HomeGlyph`; this is its fallback name.
    var symbol: String {
        switch self {
        case .back: return "arrow.uturn.backward"
        case .home: return "house"
        case .apps: return "square.grid.2x2.fill"
        case .search: return "magnifyingglass"
        case .keyboard: return "keyboard"
        case .sources: return "cable.connector"
        }
    }

    /// VoiceOver hint: what the key does, now that there is no visible caption.
    var hint: String {
        switch self {
        case .back: return "Goes back on the TV"
        case .home: return "Opens the TV home screen"
        case .apps: return "Opens the Apps folder"
        case .search: return "Searches for something to watch"
        case .keyboard: return "Types on the TV"
        case .sources: return "Changes the Samsung TV input"
        }
    }
}

/// A glass key for the Remote's navigation cluster: glyph, optional caption, and an accent fill for
/// the prominent key (Apps).
struct RemoteClusterKey<Icon: View>: View {
    let label: String
    var caption: String? = nil
    var prominent: Bool = false
    var enabled: Bool = true
    var height: CGFloat = 56
    let action: () -> Void
    @ViewBuilder let icon: () -> Icon

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                icon()
                if let caption {
                    Text(caption)
                        .scaledFont(10, .semibold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .opacity(0.7)
                }
            }
            .foregroundStyle(Color.ink)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .glassSurface(RoundedRectangle(cornerRadius: min(height * 0.42, 24), style: .continuous),
                          interactive: enabled, accent: prominent)
            .contentShape(RoundedRectangle(cornerRadius: min(height * 0.42, 24), style: .continuous))
        }
        .buttonStyle(PressStyle())
        .disabled(!enabled)
        .controlDisabled(!enabled)
        .accessibilityLabel(label)
        .accessibilityShowsLargeContentViewer {
            icon()
            Text(label)
        }
        .help(label)
    }
}

extension RemoteClusterKey where Icon == AnyView {
    /// SF Symbol key at the cluster's size and weight.
    init(symbol: String, label: String, caption: String? = nil, prominent: Bool = false,
         enabled: Bool = true, height: CGFloat = 56, action: @escaping () -> Void) {
        self.label = label
        self.caption = caption
        self.prominent = prominent
        self.enabled = enabled
        self.height = height
        self.action = action
        self.icon = { AnyView(Image(systemName: symbol).scaledFont(19, .medium)) }
    }
}

/// Phase 8: compact icon switch between the Android TV and Samsung TV remotes. Same binding and
/// behaviour as the old full-width selector; only smaller, so the pad gets the room.
struct RemoteTargetSwitch: View {
    @EnvironmentObject private var remote: RemoteModel
    var showsTitles: Bool = false
    /// Width of the icon-only switch; nil lets it fill the space it is offered (landscape column).
    var fixedWidth: CGFloat? = 108

    var body: some View {
        GlassScrubSelector(values: RemoteTarget.allCases, selection: $remote.target, height: 44) { target, selected in
            HStack(spacing: 6) {
                Image(systemName: target.symbol).scaledFont(15, .semibold)
                if showsTitles {
                    Text(target.shortTitle).scaledFont(13, .semibold).lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            .foregroundStyle(selected ? Color.ink : Color.inkAlpha(0.6))
        }
        .frame(width: showsTitles ? nil : fixedWidth)
        .frame(maxWidth: (showsTitles || fixedWidth == nil) ? .infinity : nil)
        .frame(height: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Remote for")
        .accessibilityValue(remote.target.title)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: remote.target = .samsung
            case .decrement: remote.target = .android
            @unknown default: break
            }
        }
    }
}
