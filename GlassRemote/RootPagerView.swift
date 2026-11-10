import SwiftUI

/// Hosts the four pages side by side and keeps ALL of them alive. Switching pages only moves an
/// offset: nothing is torn down or recreated, so ADB, the HID helpers, media polling and the
/// Remote page's touch state are never affected by navigation. Navigation sends no TV input.
///
/// Gesture policy (the Remote page is covered by the trackpad / D-pad):
/// - Remote: the page itself never pages. Swipe only on the dock or the two thin edge strips
///   that sit in the page's side padding, outside every control.
/// - Other pages: a horizontal-dominant swipe anywhere changes page.
struct RootPagerView: View {
    @State private var page: AppPage = .landing
    @State private var settle = 0
    @GestureState private var drag: CGFloat = 0
    @State private var measuredWidth: CGFloat = 390   // updated from the layout; used by the dock's gesture
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let edgeWidth: CGFloat = 16
    private var spring: Animation { reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.42, dampingFraction: 0.86) }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
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
            .onAppear { measuredWidth = width }
            .onChange(of: width) { measuredWidth = $0 }
        }
        .background { AmbientBackdrop() }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PageDock(page: page, select: select)
                .contentShape(Rectangle())
                .simultaneousGesture(dockDrag)
                .padding(.horizontal, 18)
                .padding(.bottom, 2)
                .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func content(for item: AppPage) -> some View {
        switch item {
        case .remote: RemoteView()
        case .player: PlayerPage()
        case .discover: DiscoverPage()
        case .apps: AppsControlsPage()
        }
    }

    private func edgeStrip(width: CGFloat) -> some View {
        Color.clear
            .frame(width: edgeWidth)
            .contentShape(Rectangle())
            .gesture(pagerDrag(width: width))
            .accessibilityHidden(true)
    }

    private func select(_ target: AppPage) {
        guard target != page else { return }
        Haptics.soft()
        withAnimation(spring) { page = target }
    }

    /// Horizontal-dominant drag; vertical scrolling inside pages is left alone.
    private func pagerDrag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 14)
            .updating($drag) { value, state, _ in
                let dx = value.translation.width, dy = value.translation.height
                state = abs(dx) > abs(dy) * 1.4 ? dx : 0
            }
            .onEnded { value in
                let dx = value.translation.width, dy = value.translation.height
                guard abs(dx) > abs(dy) * 1.4 else { return }
                let target = AppPage.target(from: page, translation: dx, predicted: value.predictedEndTranslation.width, width: width)
                if target != page { Haptics.soft() }
                withAnimation(spring) { page = target; settle += 1 }
            }
    }

    private var dockDrag: some Gesture {
        pagerDrag(width: measuredWidth)
    }
}

/// Compact Liquid Glass page switcher: the active page shows its name in a sliding glass pill.
struct PageDock: View {
    let page: AppPage
    let select: (AppPage) -> Void
    @Namespace private var pill

    var body: some View {
        GlassGroup(spacing: 6) {
            HStack(spacing: 0) {
                ForEach(AppPage.allCases) { item in
                    let selected = item == page
                    Button { select(item) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: item.symbol).scaledFont(14, .semibold)
                            if selected { Text(item.title).scaledFont(13, .semibold).lineLimit(1) }
                        }
                        .foregroundStyle(selected ? Color.white : Color.white.opacity(0.62))
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background {
                            if selected {
                                Capsule().fill(Color.clear)
                                    .glassSurface(Capsule(), interactive: true, elevated: true)
                                    .matchedGeometryEffect(id: "dockPill", in: pill)
                            }
                        }
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .layoutPriority(selected ? 1 : 0)
                    .accessibilityLabel(item.accessibilityName)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(3)
            .glassSurface(Capsule(), interactive: true)
            .animation(.spring(response: 0.38, dampingFraction: 0.84), value: page)
        }
        .frame(maxWidth: 560)
        .frame(height: 42)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pages")
    }
}
