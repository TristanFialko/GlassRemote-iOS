import SwiftUI
import UIKit

/// Plain storage for the current touch. Intentionally not observable.
final class PointerBox {
    var last: CGPoint?
    var start: Date?              // first touch time; nil = no touch in progress
    var residual = CGPoint.zero   // sub-point remainder so slow movement is not truncated away
    var moving = false            // travel passed the dead zone
    var cancelled = false         // two-finger scroll took over this touch
    var dragging = false          // touch-and-hold engaged: the left button is held down
    var token = 0                 // invalidates a pending touch-and-hold when the touch changes
}

/// Phase 7.3: explicit touch ownership between the Mouse / D-pad selector and the pad (replaces the
/// Phase 7.1 0.35 s settle delay). Every touch on the pad gets a token for the current ownership
/// epoch. The epoch moves on when a selector touch starts or ends and when the mode changes, so:
/// - a touch on the selector never sends a D-pad key, and neither does its lift;
/// - a pad touch (or hold-repeat) that was already down when the selector or mode changed is dropped;
/// - the first deliberate touch after the switch works immediately, with no waiting period.
/// Mouse mode never produces D-pad input. Main thread only; intentionally not observable.
final class RemoteInputGuard {
    private(set) var selectorTouchActive = false
    private(set) var epoch = 0
    private(set) var padToken: Int?
    private var padTouchOpen = false

    func selectorTouchChanged(_ active: Bool) {
        guard active != selectorTouchActive else { return }
        selectorTouchActive = active
        invalidate()
    }

    func modeChanged() { invalidate() }

    /// Called on every movement of a touch on the pad; only the first call of a touch takes a token.
    func padTouchChanged(isTrackpad: Bool) {
        guard !padTouchOpen else { return }
        padTouchOpen = true
        padToken = RemoteInputPolicy.token(epoch: epoch, isTrackpad: isTrackpad, selectorTouchActive: selectorTouchActive)
    }

    /// The touch lifted or was cancelled (the pad's GestureState resets on both). Its token stays valid
    /// so a tap that fires on lift is still accepted.
    func padTouchEnded() { padTouchOpen = false }

    func acceptsPadInput(isTrackpad: Bool) -> Bool {
        RemoteInputPolicy.accepts(token: padToken, epoch: epoch, isTrackpad: isTrackpad,
                                  selectorTouchActive: selectorTouchActive)
    }

    /// Clears everything, for example when the Remote leaves the screen mid-touch.
    func reset() {
        selectorTouchActive = false
        padTouchOpen = false
        invalidate()
    }

    /// The session stays open: a finger that is still down keeps a nil token until it lifts, so it can't
    /// pick up a fresh token by moving again.
    private func invalidate() {
        epoch &+= 1
        padToken = nil
    }
}

/// The pure rule behind `RemoteInputGuard`.
enum RemoteInputPolicy {
    /// The ownership token for a pad touch starting now, or nil when the pad must not own it.
    static func token(epoch: Int, isTrackpad: Bool, selectorTouchActive: Bool) -> Int? {
        (isTrackpad || selectorTouchActive) ? nil : epoch
    }

    static func accepts(token: Int?, epoch: Int, isTrackpad: Bool, selectorTouchActive: Bool) -> Bool {
        guard let token, !isTrackpad, !selectorTouchActive else { return false }
        return token == epoch
    }
}

struct RemoteView: View {
    @EnvironmentObject private var remote: RemoteModel
    @EnvironmentObject private var navigator: PageNavigator

    // Drag position lives in a reference box so updating it on every touch move does NOT invalidate
    // RemoteView's body (a plain @State CGPoint? did). Same values, same order, same behaviour.
    @State private var pointerBox = PointerBox()
    @State private var inputGuard = RemoteInputGuard()
    /// True while a finger is on the pad. GestureState resets on lift and on cancellation, so the pad's
    /// ownership session always closes (see RemoteInputGuard).
    @GestureState private var padTouching = false
    /// True while a finger is on the mouse trackpad; resets on lift AND on a system cancellation,
    /// which is the only signal SwiftUI gives when `onEnded` never arrives (audit BUG-008).
    @GestureState private var mouseTouching = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.remoteSurfaceActive) private var remoteSurfaceActive
    private var lastPoint: CGPoint? {
        get { pointerBox.last }
        nonmutating set { pointerBox.last = newValue }
    }
    @State private var dragging = false
    @State private var scrollState = TwoFingerScrollState()
    /// Phase 9 §2: the Apps folder. `folder` is its lifecycle; `folderExpanded` is the animated shell.
    @State private var folder = AppsFolderState()
    @State private var folderExpanded = false
    @State private var appsAnchor: CGRect = .zero
    @State private var appsAnchorRadius: CGFloat = 22
    @AccessibilityFocusState private var appsControlFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showKeyboard = false
    @State private var pendingPower: PowerAction?
    @State private var didAutoConnect = false
    @State private var screenshotItem: ScreenshotItem?

    @Environment(\.layoutContext) private var layoutContext

    private var isLandscape: Bool { layoutContext.isLandscape }

    /// Phase 8: portrait stacks status, mode, the dominant pad, the navigation cluster and volume.
    /// Landscape is the console stage (RemoteStageLayout): top bar, key rails under the thumbs, the
    /// pad in the middle and volume along its foot. Both go through `AnyLayout` with the same pad,
    /// mode selector and volume children, so rotating re-arranges those views instead of rebuilding
    /// them: the trackpad, its recognisers, a held key and the mouse session survive.
    private func surfaceLayout(compact: Bool) -> AnyLayout {
        let spacing = RemoteLayoutPolicy.spacing(compact: compact, isLandscape: isLandscape)
        if isLandscape {
            return AnyLayout(RemoteStageLayout(spacing: spacing, columnSpacing: RemoteLayoutPolicy.stageColumnSpacing))
        }
        return AnyLayout(VStackLayout(spacing: spacing))
    }

    var body: some View {
        ZStack {
            GeometryReader { proxy in
                let compact = !isLandscape && RemoteLayoutPolicy.isCompact(height: proxy.size.height)
                let surface = surfaceLayout(compact: compact)
                let insets = RemoteLayoutPolicy.stageInsets
                let stageWidth = max(proxy.size.width - insets.leading - insets.trailing, 0)
                let stageHeight = max(proxy.size.height - insets.top - insets.bottom, 0)
                // Continuation §C3: the landscape volume deck's height for this stage.
                let volumeThickness = isLandscape
                    ? RemoteLayoutPolicy.landscapeDeckHeight(stageHeight: stageHeight,
                                                             spacing: RemoteLayoutPolicy.spacing(compact: false, isLandscape: true))
                    : RemoteLayoutPolicy.volumeThickness(compact: compact)
                let keyHeight = RemoteLayoutPolicy.railKeyHeight(stageHeight: stageHeight)
                surface {
                    header(stageWidth: stageWidth)
                    if remote.target == .samsung {
                        samsungControls(compact: compact, railKeyHeight: keyHeight)
                    } else {
                        androidControls(compact: compact, railKeyHeight: keyHeight)
                    }
                    volumeBar(thickness: volumeThickness)
                        .remoteStage(.deck)
                    if isLandscape && !folder.isVisible {
                        // Continuation §D: the free space in the key rails is where a vertical page
                        // swipe may start on the Remote; everything else on it is a control.
                        PagerSwipeArea().remoteStage(.gap)
                        PagerSwipeArea().remoteStage(.gap)
                    }
                }
                .padding(insets)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            }
            // The Remote keeps its layout while the folder's search keyboard is up; the folder moves.
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .accessibilityHidden(folder.isExpanded)

            if folder.isVisible {
                AppsFolderOverlay(state: folder, expanded: folderExpanded, anchor: appsAnchor,
                                  anchorCornerRadius: appsAnchorRadius, isLandscape: isLandscape,
                                  onDismiss: { dismissFolder($0) },
                                  onLaunch: { launchFromFolder($0) },
                                  onRestart: { restartFromFolder($0) },
                                  onMounted: { folderMounted() })
                    .zIndex(1)
            }
        }
        // The folder belongs to the Android remote on the Remote page: switching device, leaving the
        // page or removing the view closes it at once. Rotation and connection changes keep it open.
        .onChange(of: remote.target) { _, _ in resetFolder() }
        .onChange(of: navigator.page) { _, page in if page != .remote { resetFolder() } }
        .onDisappear { resetFolder() }
        .themedSheet()
        // Text follows Dynamic Type, capped so the fixed remote layout keeps fitting (tighter in
        // landscape, where the columns have less height).
        .dynamicTypeSize(isLandscape ? ...DynamicTypeSize.xLarge : ...DynamicTypeSize.xxxLarge)
        .sheet(isPresented: $remote.showConnection) { ConnectionSheet().environmentObject(remote) }
        .sheet(isPresented: $showKeyboard) { KeyboardSheet().environmentObject(remote) }
        .sheet(item: $screenshotItem) { item in ScreenshotSheet(item: item) }
        .confirmationDialog(
            pendingPower?.title ?? "",
            isPresented: Binding(get: { pendingPower != nil }, set: { if !$0 { pendingPower = nil } }),
            titleVisibility: .visible,
            presenting: pendingPower
        ) { action in
            Button(action.confirmLabel, role: action.isDestructive ? .destructive : nil) { perform(action) }
        } message: { action in
            Text(action.message)
        }
        .task {
            guard !didAutoConnect else { return }
            didAutoConnect = true
            Haptics.prepare()
            if remote.isFirstRun {
                // Nothing saved yet: open the connection sheet, which scans for devices.
                remote.showConnection = true
            } else if !remote.connected && !remote.requiresUserReconnect {
                remote.connect()
            }
        }
    }

    // MARK: - Compositions

    /// Android TV: mode selector, the pad and the navigation keys (one row in portrait, a rail under
    /// each thumb in landscape).
    @ViewBuilder
    private func androidControls(compact: Bool, railKeyHeight: CGFloat) -> some View {
        Group {
            // Landscape: centred over the pad in the top bar.
            modeRow(compact: compact)
                .remoteStage(.topCenter)
            // The pad is the point of this page: it takes every spare point and never shrinks below a
            // comfortable size.
            controlSurface
                .frame(minHeight: RemoteLayoutPolicy.padMinHeight(compact: compact, isLandscape: isLandscape),
                       maxHeight: .infinity)
                .layoutPriority(1)
                .remoteStage(.pad)
            if isLandscape {
                navRail(landscapeRails.leading, height: railKeyHeight)
                    .remoteStage(.leading)
                navRail(landscapeRails.trailing, height: railKeyHeight)
                    .remoteStage(.trailing)
            } else {
                navCluster(compact: compact)
            }
        }
    }

    private var landscapeRails: (leading: [RemoteNavKey], trailing: [RemoteNavKey]) {
        RemoteNavKey.landscapeRails(samsungLinked: remote.tvVolumeEnabled)
    }

    /// Samsung TV: a permanent trackpad and a short key set replace the Android controls.
    @ViewBuilder
    private func samsungControls(compact: Bool, railKeyHeight: CGFloat) -> some View {
        Group {
            if showsSamsungBanner && !isLandscape {
                SamsungLinkBanner()
            }
            SamsungTrackpad()
                .disabled(!remote.samsungRemoteReady)
                .frame(minHeight: RemoteLayoutPolicy.padMinHeight(compact: compact, isLandscape: isLandscape),
                       maxHeight: .infinity)
                .layoutPriority(1)
                .remoteStage(.pad)
            if isLandscape {
                // The banner floats over the top of the pad, which is disabled while it shows. Declared
                // after the pad so it draws above it.
                if showsSamsungBanner {
                    SamsungLinkBanner()
                        .remoteStage(.overPad)
                }
                // A rail under each thumb: navigation and channel on the left, transport and mute on the
                // right beside the volume deck. No key appears twice.
                ForEach(Array(SamsungRemoteLayout.landscapeLeadingRail.enumerated()), id: \.offset) { _, group in
                    SamsungKeyRow(items: group, height: railKeyHeight, captions: true, axis: .vertical)
                        .remoteStage(.leading)
                }
                ForEach(Array(SamsungRemoteLayout.landscapeTrailingRail.enumerated()), id: \.offset) { _, group in
                    SamsungKeyRow(items: group, height: railKeyHeight, captions: true, axis: .vertical)
                        .remoteStage(.trailing)
                }
            } else {
                ForEach(Array(SamsungRemoteLayout.primaryRows.enumerated()), id: \.offset) { _, row in
                    SamsungKeyRow(items: row, height: compact ? 48 : 54)
                }
            }
        }
        .opacity(remote.samsungRemoteReady ? 1 : 0.92)
    }

    // MARK: - Header

    private var showsSamsungBanner: Bool {
        SamsungRemoteLayout.showsBanner(enabled: remote.tvVolumeEnabled, state: remote.samsungState)
    }

    /// Status pill (opens the live-action menu), the device switch and power. Portrait: one row.
    /// Landscape: the two ends of the top bar, the pill leading and the switch with power trailing (the
    /// mode selector sits between them, over the pad). The pill drops to the short name and then the
    /// chevron when the room is tight (RemoteLayoutPolicy.pillStyle).
    private func header(stageWidth: CGFloat) -> some View {
        Group {
            if isLandscape {
                RemoteStatusMenu(pillStyle: RemoteLayoutPolicy.pillStyle(width: RemoteLayoutPolicy.statusWidth(stageWidth: stageWidth)),
                                 onScreenshot: takeScreenshot)
                    .remoteStage(.topLeading)
                HStack(spacing: 8) {
                    RemoteTargetSwitch()
                    PowerMenuButton { pendingPower = $0 }
                }
                .remoteStage(.topTrailing)
            } else {
                HStack(spacing: 8) {
                    // The switch is 108 pt, power 44 pt, two 8 pt gaps.
                    RemoteStatusMenu(pillStyle: RemoteLayoutPolicy.pillStyle(width: stageWidth - 168),
                                     onScreenshot: takeScreenshot)
                    RemoteTargetSwitch()
                    PowerMenuButton { pendingPower = $0 }
                }
            }
        }
        .foregroundStyle(Color.ink)
    }

    private func takeScreenshot() {
        Task {
            if let image = await remote.captureScreenshot() { screenshotItem = ScreenshotItem(image: image) }
        }
    }

    private func perform(_ action: PowerAction) {
        switch action {
        case .standby: remote.standby()
        case .restartLauncher: remote.restartLauncher()
        case .restartBox: remote.restartBox()
        case .everythingOff: remote.turnEverythingOff()
        }
    }

    // MARK: - Apps launcher

    /// Opens the folder out of the Apps control. Any pad touch, drag or held mouse button is ended
    /// first, so nothing keeps moving on the TV under the folder.
    private func openFolder() {
        cancelPointer()
        inputGuard.padTouchEnded()
        inputGuard.modeChanged()
        let wasVisible = folder.isVisible
        guard folder.open() != nil else { return }
        // A new overlay expands once it is mounted (folderMounted); a folder that is still
        // collapsing turns around from where it is.
        if wasVisible { animateShell(expanded: true) }
    }

    private func folderMounted() {
        guard folder.phase == .opening, !folderExpanded else { return }
        animateShell(expanded: true)
    }

    private func dismissFolder(_ reason: AppsFolderState.DismissReason) {
        guard folder.dismiss(reason) != nil else { return }
        animateShell(expanded: false)
    }

    /// One spring for shell, tiles and icon highlight. The completion settles only the transition it
    /// belongs to (AppsFolderState.generation), so an interrupted animation can't strand the state.
    private func animateShell(expanded: Bool) {
        let generation = folder.generation
        // Continuation §A4: quicker spring; under Reduce Motion a short cross-fade in place.
        let reduced = reduceMotion || MotionPreference.reduced
        withAnimation(AppsFolderMotion.animation(opening: expanded, reduceMotion: reduced)) {
            folderExpanded = expanded
        } completion: {
            folder.settle(generation)
            if !folder.isVisible { appsControlFocused = true }
        }
    }

    private func resetFolder() {
        guard folder.isVisible || folderExpanded else { return }
        folder.reset()
        folderExpanded = false
    }

    private func launchFromFolder(_ app: TVApp) {
        guard folder.acceptsLaunch else { return }
        remote.launch(app)
        dismissFolder(.launched)
    }

    private func restartFromFolder(_ app: TVApp) {
        guard folder.acceptsLaunch else { return }
        remote.restartApp(app)
        dismissFolder(.launched)
    }

    private func recordAppsAnchor(_ frame: CGRect, radius: CGFloat) {
        if frame != appsAnchor { appsAnchor = frame }
        if radius != appsAnchorRadius { appsAnchorRadius = radius }
    }

    // MARK: - Mode selector

    private func modeRow(compact: Bool) -> some View {
        ModeSelector(isMouse: $remote.isTrackpad,
                     segmentHeight: RemoteLayoutPolicy.selectorHeight(compact: compact, isLandscape: isLandscape) - 8,
                     onTouchChange: { inputGuard.selectorTouchChanged($0) })
            .onChange(of: remote.isTrackpad) { _, _ in inputGuard.modeChanged() }
    }

    // MARK: - Mouse / D-pad surface

    @ViewBuilder
    private var controlSurface: some View {
        if remote.isTrackpad { mouseSurface } else { dpadSurface }
    }

    private static let tapMaxNanos: UInt64 = 450_000_000   // a touch held longer than this is not a tap
    private static let deadZone: CGFloat = 3                    // points before the cursor starts moving

    private static let holdToDragNanos: UInt64 = 500_000_000  // touch and hold this long to start a drag

    private func resetPointer() {
        let box = pointerBox
        box.token += 1                      // cancels a pending touch-and-hold
        box.last = nil; box.start = nil; box.moving = false
        box.cancelled = false; box.residual = .zero
        box.dragging = false
    }

    /// Releases the button if a touch-and-hold drag is in progress.
    private func releaseDragIfNeeded() {
        let box = pointerBox
        if box.dragging {
            box.dragging = false
            remote.mouseButton(0)
        }
    }

    /// Drops the touch in progress if it is interrupted (view hidden, Apps grid opened, ...).
    private func cancelPointer() {
        releaseDragIfNeeded()
        resetPointer()
    }

    /// After half a second of holding still, press the left button so the next movement drags.
    private func armHoldToDrag() {
        let box = pointerBox
        box.token += 1
        let token = box.token
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.holdToDragNanos)
            guard box.token == token, box.start != nil, !box.moving, !box.cancelled,
                  !box.dragging, !scrollState.suppressesClicks else { return }
            box.dragging = true
            remote.mouseButton(1)
            Haptics.medium()
        }
    }

    private var mouseSurface: some View {
        let shape = RoundedRectangle(cornerRadius: 36, style: .continuous)
        // v5 §6: no instructions drawn inside the surface; VoiceOver keeps them as a hint.
        return Color.clear
            .glassSurface(shape, elevated: true)
            .contentShape(shape)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Trackpad")
            .accessibilityHint(RemoteSurfaceHints.androidTrackpad)
            .background {
                TwoFingerScroll(
                    state: scrollState,
                    onScroll: { wheel, hscroll in remote.mouse(wheel: wheel, hscroll: hscroll) },
                    onTwoFingerTap: {
                        Haptics.light()
                        remote.key("BACK")
                    }
                )
                .environment(\.remoteSurfaceActive, remoteSurfaceActive && !folder.isVisible)
            }
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .updating($mouseTouching) { _, state, _ in state = true }
                .onChanged { value in
                    let box = pointerBox
                    if box.start == nil {
                        // First touch: nothing is sent. A touch alone never clicks.
                        box.start = Date()
                        box.residual = .zero
                        box.moving = false
                        box.cancelled = false
                        box.dragging = false
                        box.last = value.location
                        armHoldToDrag()
                    }

                    // Two fingers = scroll. Abandon this touch (and any held button) cleanly.
                    if scrollState.isActive {
                        releaseDragIfNeeded()
                        box.cancelled = true
                        box.last = value.location
                        return
                    }

                    let travel = max(abs(value.translation.width), abs(value.translation.height))
                    if !box.moving {
                        // Small dead zone so a tap does not nudge the cursor off its target.
                        guard travel >= Self.deadZone else { return }
                        box.moving = true
                        box.last = value.location   // start from here: no jump when it engages
                        return
                    }

                    if let previous = box.last {
                        let deltaX = value.location.x - previous.x
                        let deltaY = value.location.y - previous.y
                        // Base gain from the sensitivity setting; fast swipes get up to 60 % extra
                        // so a long reach is quick while slow movements stay precise.
                        var gain = CGFloat(remote.mouseSensitivity)
                        if remote.mouseAcceleration {
                            let speed = hypot(deltaX, deltaY)
                            gain *= 1 + 0.6 * min(1, max(0, (speed - 3) / 20))
                        }
                        let fx = deltaX * gain + box.residual.x
                        let fy = deltaY * gain + box.residual.y
                        let dx = Int(fx.rounded(.towardZero))
                        let dy = Int(fy.rounded(.towardZero))
                        box.residual = CGPoint(x: fx - CGFloat(dx), y: fy - CGFloat(dy))
                        if dx != 0 || dy != 0 { remote.mouseMove(dx: dx, dy: dy) }
                    }
                    box.last = value.location
                }
                .onEnded { value in
                    let box = pointerBox
                    if box.dragging {
                        // Touch-and-hold drag finished: let go of the button.
                        releaseDragIfNeeded()
                        Haptics.light()
                        resetPointer()
                        return
                    }
                    let held = box.start.map { Date().timeIntervalSince($0) } ?? 0
                    let wasTap = !box.moving && !box.cancelled
                        && held < Double(Self.tapMaxNanos) / 1_000_000_000
                        && abs(value.translation.width) < 8 && abs(value.translation.height) < 8
                        && !scrollState.suppressesClicks
                    if wasTap {
                        remote.mouseButton(1)
                        Haptics.light()
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 45_000_000)
                            remote.mouseButton(0)
                        }
                    }
                    resetPointer()
                })
            .onChange(of: folder.isVisible) { _, _ in cancelPointer() }
            .onChange(of: mouseTouching) { _, touching in
                // A normal lift also resets the state; give `onEnded` a moment, then clean up a touch
                // the system took away (no end ever came): release any held button, no cursor jump.
                guard !touching, let started = pointerBox.start else { return }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: InputCancellation.lostEndGrace)
                    if pointerBox.start == started { cancelPointer() }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { cancelPointer() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .glassRemoteCancelTouches)) { _ in
                cancelPointer()
            }
            .onDisappear { cancelPointer() }
    }

    private var dpadSurface: some View {
        let shape = RoundedRectangle(cornerRadius: 36, style: .continuous)
        return GeometryReader { geo in
            let size = RemoteLayoutPolicy.dpadDiameter(for: geo.size)
            GlassDpad(size: size) { key in
                guard inputGuard.acceptsPadInput(isTrackpad: remote.isTrackpad) else { return }
                remote.routedKey(key)
            }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // Phase 9 §1.2: same elevated glass as the mouse pad and the Samsung pad, so every central
        // surface has the same geometry and visual weight.
        .glassSurface(shape, elevated: true)
        // Phase 7.3: every touch on the pad opens an ownership session (see RemoteInputGuard). It runs
        // alongside the keys and the swipe and never consumes the touch.
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .updating($padTouching) { _, state, _ in state = true }
                .onChanged { _ in inputGuard.padTouchChanged(isTrackpad: remote.isTrackpad) }
        )
        .onChange(of: padTouching) { _, touching in
            if !touching { inputGuard.padTouchEnded() }
        }
        // Swipe anywhere on the pad to send an arrow, like the Apple TV remote.
        .simultaneousGesture(
            DragGesture(minimumDistance: 28)
                .onEnded { value in
                    guard inputGuard.acceptsPadInput(isTrackpad: remote.isTrackpad) else { return }
                    let w = value.translation.width, h = value.translation.height
                    let name = abs(w) > abs(h) ? (w > 0 ? "RIGHT" : "LEFT") : (h > 0 ? "DOWN" : "UP")
                    Haptics.soft()
                    remote.routedKey(name)
                }
        )
        .onDisappear { inputGuard.padTouchEnded() }
    }

    // MARK: - Navigation and volume

    /// Portrait secondary navigation: one row (Apps is the folder key). Phase 9 §1.1: icon-only,
    /// full-size hit targets, names for VoiceOver, the pointer tooltip and the Large Content Viewer.
    private func navCluster(compact: Bool) -> some View {
        let keys = RemoteNavKey.cluster(isLandscape: false, samsungLinked: remote.tvVolumeEnabled)
        let height: CGFloat = compact ? 48 : 56
        return GlassGroup(spacing: 10) {
            HStack(spacing: 8) {
                ForEach(keys, id: \.self) { key in navKey(key, height: height) }
            }
        }
    }

    /// Landscape: one rail of the same keys, stacked under a thumb.
    private func navRail(_ keys: [RemoteNavKey], height: CGFloat) -> some View {
        GlassGroup(spacing: 10) {
            VStack(spacing: 10) {
                ForEach(keys, id: \.self) { key in navKey(key, height: height) }
            }
        }
    }

    @ViewBuilder
    private func navKey(_ key: RemoteNavKey, height: CGFloat) -> some View {
        switch key {
        case .back:
            RemoteClusterKey(symbol: key.symbol, label: key.title, height: height) {
                remote.routedKey("BACK")
            }
            .accessibilityHint(key.hint)
        case .home:
            RemoteClusterKey(label: key.title, height: height, action: { remote.routedKey("HOME") }) {
                HomeGlyph()
            }
            .accessibilityHint(key.hint)
        case .apps:
            RemoteClusterKey(symbol: key.symbol, label: key.title, prominent: folder.highlightsSource,
                             height: height) { openFolder() }
                .accessibilityValue(RemoteLayoutPolicy.appCountLabel(remote.apps.count))
                .accessibilityHint(key.hint)
                .accessibilityFocused($appsControlFocused)
                .onGeometryChange(for: CGRect.self) { proxy in proxy.frame(in: .global) } action: { frame in
                    recordAppsAnchor(frame, radius: min(height * 0.42, 24))
                }
        case .search:
            RemoteClusterKey(symbol: key.symbol, label: key.title, height: height) {
                navigator.openSearch()
            }
            .accessibilityHint(key.hint)
        case .keyboard:
            RemoteClusterKey(symbol: key.symbol, label: key.title, height: height) {
                showKeyboard = true
            }
            .accessibilityHint(key.hint)
        case .sources:
            // Opens the Samsung TV's own input/source menu (KEY_SOURCE) over the Samsung link.
            RemoteClusterKey(symbol: key.symbol, label: key.title, height: height) {
                remote.samsungKey(.source)
            }
            .accessibilityHint(key.hint)
        }
    }

    private func volumeBar(thickness: CGFloat) -> some View {
        // One shared position (RemoteModel.volumeSliderFraction) with Now Playing's row, so the two
        // rows can never disagree; readings reach it only through VolumeSync in the model.
        GlassVolumeSlider(value: Binding(get: { remote.volumeSliderFraction },
                                         set: { remote.userMovedVolumeSlider(to: $0) }),
                          scale: remote.volumeScale, thickness: thickness,
                          onDragChange: { remote.volumeDragChanged($0) },
                          unavailableReason: remote.volumeUnavailableReason,
                          outputLabel: remote.volumeOutputLabel)
            .onAppear { remote.refreshDeviceVolume() }
    }
}
