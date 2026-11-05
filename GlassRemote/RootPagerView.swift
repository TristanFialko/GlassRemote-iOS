import SwiftUI

/// Hosts the three pages side by side and keeps ALL of them alive. Switching pages only moves an
/// offset: nothing is torn down or recreated, so ADB, the HID helpers, media polling and the
/// Remote page's touch state are never affected by navigation. Navigation sends no TV input.
///
/// Gesture policy (the Remote page is covered by the trackpad / D-pad):
/// - Remote: the page itself never pages. Swipe only on the dock or the two thin edge strips
///   that sit in the page's side padding, outside every control.
/// - Other pages: a horizontal-dominant swipe anywhere changes page.
struct RootPagerView: View {
    @StateObject private var navigator = PageNavigator()
    @State private var settle = 0
    @GestureState private var drag: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let edgeWidth: CGFloat = 16
    private var page: AppPage { navigator.page }
    private var spring: Animation { reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.42, dampingFraction: 0.86) }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .bottom) {
                ZStack {
                    HStack(spacing: 0) {
                        ForEach(AppPage.allCases) { item in
                            content(for: item)
                                .frame(width: width, height: geo.size.height)
                                .allowsHitTesting(item == page)
                                .accessibilityHidden(item != page)
                        }
                    }
                    .frame(width: width * CGFloat(AppPage.allCases.count), alignment: .leading)
                    .offset(x: -CGFloat(page.rawValue) * width + AppPage.resisted(drag, on: page))
                    .frame(width: width, alignment: .leading)
                    .animation(spring, value: settle)
                    .animation(spring, value: page)

                    if page == .remote {
                        HStack {
                            edgeStrip(width: width)
                            Spacer(minLength: 0)
                            edgeStrip(width: width)
                        }
                    }
                }
                .clipped()
                .simultaneousGesture(pagerDrag(width: width), including: page == .remote ? .none : .all)

                PageDock()
                    .padding(.horizontal, 14)
                    .padding(.bottom, 4)
            }
        }
        .background { AmbientBackdrop() }
        .environmentObject(navigator)
    }

    @ViewBuilder
    private func content(for item: AppPage) -> some View {
        switch item {
        case .remote: RemoteView().padding(.bottom, DockMetrics.clearance)
        case .player: PlayerPage()
        case .discover: DiscoverPage()
        }
    }

    private func edgeStrip(width: CGFloat) -> some View {
        Color.clear
            .frame(width: edgeWidth)
            .contentShape(Rectangle())
            .gesture(pagerDrag(width: width))
            .accessibilityHidden(true)
    }

    /// Horizontal-dominant drag; vertical scrolling inside pages is left alone.
    private func pagerDrag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 14)
            .updating($drag) { value, state, _ in
                let dx = value.translation.width, dy = value.translation.height
                state = (!ScrubTouch.shared.isActive && abs(dx) > abs(dy) * 1.4) ? dx : 0
            }
            .onEnded { value in
                let dx = value.translation.width, dy = value.translation.height
                guard !ScrubTouch.shared.isActive, abs(dx) > abs(dy) * 1.4 else { return }
                let target = AppPage.target(from: page, translation: dx, predicted: value.predictedEndTranslation.width, width: width)
                if target != page { Haptics.soft() }
                withAnimation(spring) { navigator.page = target; settle += 1 }
            }
    }
}

/// Floating Liquid Glass page bar. Slide a finger along it and the glass bubble follows, switching
/// pages as it crosses each icon (like the YouTube bar). Tapping works the same way.
/// The icon / caption labels are drawn above the glass (see `GlassScrubSelector`).
struct PageDock: View {
    @EnvironmentObject private var navigator: PageNavigator

    var body: some View {
        GlassScrubSelector(
            values: AppPage.allCases,
            selection: Binding(get: { navigator.page }, set: { navigator.go($0, haptic: false) }),
            height: DockMetrics.height, inset: 5
        ) { item, selected in
            VStack(spacing: 3) {
                Image(systemName: item.symbol).scaledFont(21, .semibold)
                Text(item.title).scaledFont(10, .semibold).lineLimit(1)
            }
            .foregroundStyle(selected ? Color.white : Color.white.opacity(0.62))
            .accessibilityLabel(item.title)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pages")
    }
}
