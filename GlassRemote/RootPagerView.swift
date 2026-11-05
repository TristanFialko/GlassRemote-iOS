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
    @StateObject private var navigator = PageNavigator()
    @State private var settle = 0
    @GestureState private var drag: CGFloat = 0
    @State private var measuredWidth: CGFloat = 390   // updated from the layout; used by the dock's gesture
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

                PageDock(page: page, select: { navigator.go($0) })
                    .padding(.horizontal, 14)
                    .padding(.bottom, 4)
                    .simultaneousGesture(pagerDrag(width: measuredWidth))
            }
            .onAppear { measuredWidth = width }
            .onChange(of: width) { measuredWidth = $0 }
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
                withAnimation(spring) { navigator.page = target; settle += 1 }
            }
    }
}

/// Floating Liquid Glass page bar: one wide glass capsule, one sliding glass lens behind the
/// selected page (icon over caption, like the system tab bar). On iOS 26 both are native glass in
/// one container so the lens refracts and morphs; earlier systems get the material fallback.
struct PageDock: View {
    let page: AppPage
    let select: (AppPage) -> Void
    @Namespace private var ns

    private let inset: CGFloat = 5

    var body: some View {
        GlassGroup(spacing: 10) {
            GeometryReader { geo in
                let seg = (geo.size.width - inset * 2) / CGFloat(AppPage.allCases.count)
                ZStack(alignment: .leading) {
                    Color.clear.glassBar(Capsule()).glassMorph("dock", in: ns)
                    Color.clear
                        .frame(width: seg, height: DockMetrics.height - inset * 2)
                        .glassLens(Capsule())
                        .glassMorph("lens", in: ns)
                        .offset(x: inset + seg * CGFloat(page.rawValue))
                        .animation(.spring(response: 0.40, dampingFraction: 0.80), value: page)
                    HStack(spacing: 0) {
                        ForEach(AppPage.allCases) { item in
                            let selected = item == page
                            Button { select(item) } label: {
                                VStack(spacing: 3) {
                                    Image(systemName: item.symbol).scaledFont(21, .semibold)
                                    Text(item.title).scaledFont(10, .semibold).lineLimit(1)
                                }
                                .foregroundStyle(selected ? Color.white : Color.white.opacity(0.62))
                                .frame(width: seg, height: DockMetrics.height)
                                .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(item.accessibilityName)
                            .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }
                    .padding(.horizontal, inset)
                }
            }
            .frame(height: DockMetrics.height)
        }
        .frame(height: DockMetrics.height)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pages")
    }
}
