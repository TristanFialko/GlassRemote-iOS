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

struct RemoteView: View {
    @EnvironmentObject private var remote: RemoteModel
    @EnvironmentObject private var navigator: PageNavigator

    // Drag position lives in a reference box so updating it on every touch move does NOT invalidate
    // RemoteView's body (a plain @State CGPoint? did). Same values, same order, same behaviour.
    @State private var pointerBox = PointerBox()
    private var lastPoint: CGPoint? {
        get { pointerBox.last }
        nonmutating set { pointerBox.last = newValue }
    }
    @State private var dragging = false
    @State private var scrollState = TwoFingerScrollState()
    @State private var appsExpanded = false
    @State private var showKeyboard = false
    @State private var pendingPower: PowerAction?
    @State private var didAutoConnect = false
    @State private var screenshotItem: ScreenshotItem?
    @State private var showDeviceInfo = false
    @State private var showThemes = false
    @ObservedObject private var favourites = AppFavourites.shared
    @State private var volumeSliderValue: Double = 0.5
    @State private var externalVolumeEcho: Double?

    /// The Apps grid belongs to the Android remote only. Everything that reacts to it (page height,
    /// scrolling, pad dimming) reads this, so the Samsung remote never inherits the expanded layout.
    /// `appsExpanded` itself is kept, so the state survives a round trip to Samsung and back.
    private var androidExpanded: Bool { appsExpanded && remote.target == .android }

    @Environment(\.layoutContext) private var layoutContext

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 9), count: 3)

    /// Short screens (iPhone SE / mini class): tighter gaps so the larger pad never pushes the
    /// navigation keys or the volume bar out of reach.
    private func compact(_ proxy: GeometryProxy) -> Bool { proxy.size.height < 600 }

    /// Portrait keeps the Phase 5 stack exactly. Landscape puts the controls in a column beside a
    /// full-height pad. Both go through `AnyLayout`, so rotating re-arranges the same views instead of
    /// rebuilding them: the trackpad, its recognisers, a held button and the mouse session survive.
    private func surfaceLayout(_ proxy: GeometryProxy) -> AnyLayout {
        let spacing: CGFloat = compact(proxy) ? 6 : 8
        if layoutContext.isLandscape {
            return AnyLayout(RemoteLandscapeLayout(spacing: spacing, columnSpacing: 14, maxColumnWidth: 340,
                                                   padMinHeight: 200, padMaxHeight: androidExpanded ? 250 : nil))
        }
        return AnyLayout(VStackLayout(spacing: spacing))
    }

    var body: some View {
        GeometryReader { proxy in
            let surface = surfaceLayout(proxy)
            ScrollView(.vertical, showsIndicators: false) {
                surface {
                    header
                    deviceSelector
                    if remote.target == .samsung {
                        // Samsung mode: a permanent trackpad and a short key set replace the Android controls.
                        SamsungRemotePanel()
                            .layoutValue(key: RemotePadSlot.self, value: true)
                    } else {
                        appsSection
                        modeRow
                        // The pad is the point of this page: it takes every spare point (including the room the
                        // old mini-player used) and never shrinks below a comfortable size.
                        controlSurface
                            .frame(minHeight: compact(proxy) ? 200 : 250, maxHeight: androidExpanded ? 250 : CGFloat.infinity)
                            .layoutPriority(1)
                            .layoutValue(key: RemotePadSlot.self, value: true)
                        navRow
                            .layoutValue(key: RemoteBottomSlot.self, value: true)
                    }
                    volumeBar
                        .layoutValue(key: RemoteBottomSlot.self, value: true)
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 8)
                .frame(height: androidExpanded ? nil : proxy.size.height)
            }
            // The page only scrolls while the Apps grid pushes content below the fold.
            .scrollDisabled(!androidExpanded)
        }
        .themedSheet()
        // Text follows Dynamic Type, capped so the fixed remote layout keeps fitting (tighter in
        // landscape, where the control column has less height).
        .dynamicTypeSize(layoutContext.isLandscape ? ...DynamicTypeSize.xLarge : ...DynamicTypeSize.xxxLarge)
        .sheet(isPresented: $remote.showConnection) { ConnectionSheet().environmentObject(remote) }
        .sheet(isPresented: $showThemes) { ThemePickerSheet() }
        .sheet(isPresented: $showKeyboard) { KeyboardSheet().environmentObject(remote) }
        .sheet(item: $screenshotItem) { item in ScreenshotSheet(item: item) }
        .sheet(isPresented: $showDeviceInfo) { DeviceInfoSheet().environmentObject(remote) }
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

    // MARK: - Backdrop

    private var backdrop: some View { AmbientBackdrop() }

    // MARK: - Header

    private var statusLabel: String {
        switch remote.linkState {
        case .reconnectNeeded: return "Reconnect needed"
        case .connected: return "Connected"
        case .connecting: return "Connecting…"
        case .offline: return "Offline"
        }
    }

    private var androidOK: Bool { remote.connected && !remote.requiresUserReconnect }

    private var samsungDotColor: Color {
        switch remote.samsungState {
        case .connected: return .green
        case .connecting, .pairing: return .yellow
        case .denied, .unreachable: return .orange
        case .off: return Color.inkFaint(0.35)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            GlobalMenuButton(boxOnline: androidOK, onScreenshot: takeScreenshot, onDeviceInfo: { showDeviceInfo = true }, onThemes: { showThemes = true })

            // Status only: it does not open anything. Reconnecting lives in the menu.
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Circle().fill(androidOK ? Color.green : Color.orange).frame(width: 8, height: 8)
                    Text("Box").scaledFont(12, .semibold)
                }
                if remote.tvVolumeEnabled {
                    HStack(spacing: 6) {
                        Circle().fill(samsungDotColor).frame(width: 8, height: 8)
                        Text("TV").scaledFont(12, .semibold)
                    }
                }
            }
            .foregroundStyle(Color.ink.opacity(0.88))
            .padding(.horizontal, 14)
            .frame(height: 36)
            .glassSurface(Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Connection: box \(statusLabel)" + (remote.tvVolumeEnabled ? ", Samsung \(remote.samsungState.label)" : ""))

            Spacer(minLength: 0)

            PowerMenuButton { pendingPower = $0 }
        }
        .foregroundStyle(Color.ink)
    }

    private func takeScreenshot() {
        Task {
            if let image = await remote.captureScreenshot() { screenshotItem = ScreenshotItem(image: image) }
        }
    }

    private var deviceSelector: some View {
        GlassSegmented(
            items: RemoteTarget.allCases.map { GlassSegmented<RemoteTarget>.Item(value: $0, title: $0.title, symbol: $0.symbol) },
            selection: $remote.target,
            height: 38
        )
    }

    private func perform(_ action: PowerAction) {
        switch action {
        case .standby: remote.standby()
        case .restartLauncher: remote.restartLauncher()
        case .restartBox: remote.restartBox()
        case .everythingOff: remote.turnEverythingOff()
        }
    }

    // MARK: - Apps (collapsed by default)

    /// Favourites first (in the order they were starred), then the rest in their normal order.
    private var launcherApps: [TVApp] {
        let favs = favourites.packages.compactMap { pkg in remote.apps.first { $0.package == pkg } }
        return favs + remote.apps.filter { app in !favourites.contains(app.package) }
    }

    private var appsSection: some View {
        VStack(spacing: 10) {
            Button {
                Haptics.soft()
                withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) { appsExpanded.toggle() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "square.grid.2x2").scaledFont(19, .medium)
                    Text("Apps").scaledFont(15, .semibold)
                    Spacer()
                    if !appsExpanded {
                        Text("\(remote.apps.count)").scaledFont(13).foregroundStyle(Color.ink.opacity(0.65))
                    }
                    Image(systemName: appsExpanded ? "chevron.up" : "chevron.down")
                        .scaledFont(14, .semibold)
                }
                .foregroundStyle(Color.ink)
                .padding(.horizontal, 18)
                .frame(height: appsExpanded ? 40 : 46)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(appsExpanded ? "Hide apps" : "Show apps")

            if appsExpanded {
                appGrid
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, appsExpanded ? 8 : 0)
        .padding(.bottom, appsExpanded ? 10 : 0)
        .frame(maxWidth: .infinity)
        .glassSurface(RoundedRectangle(cornerRadius: 30, style: .continuous), interactive: !appsExpanded)
    }

    // Same artwork, order and tile construction as before; only the surrounding panel is new.
    private var appGrid: some View {
        LazyVGrid(columns: columns, spacing: 9) {
            ForEach(launcherApps) { app in
                Button {
                    remote.launch(app)
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) { appsExpanded = false }
                } label: {
                    AppIconImage(asset: "\(app.asset)_dark")
                        .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 17, style: .continuous)
                                .strokeBorder(Color.ink.opacity(0.22), lineWidth: 1)
                        }
                        .background {
                            RoundedRectangle(cornerRadius: 17, style: .continuous)
                                .fill(Color.ink.opacity(0.07))   // flat fill: no material on top of the glass panel
                        }
                        .shadow(color: .black.opacity(0.34), radius: 8, y: 4)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(1, contentMode: .fit)
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel(app.name)
                .overlay(alignment: .topTrailing) {
                    if favourites.contains(app.package) {
                        Image(systemName: "star.fill").font(.system(size: 10)).foregroundStyle(.yellow).padding(5)
                    }
                }
                .contextMenu {
                    Button { favourites.toggle(app.package) } label: {
                        Label(favourites.contains(app.package) ? "Remove favourite" : "Favourite",
                              systemImage: favourites.contains(app.package) ? "star.slash" : "star")
                    }
                    Button(role: .destructive) {
                        remote.restartApp(app)
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) { appsExpanded = false }
                    } label: {
                        Label("Restart \(app.name)", systemImage: "arrow.clockwise")
                    }
                }
            }
        }
    }

    // MARK: - Mode selector

    private var modeRow: some View {
        ModeSelector(isMouse: $remote.isTrackpad, segmentHeight: 32)
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
        return Color.clear
            .glassSurface(shape, elevated: true)
            .overlay(alignment: .bottom) {
                Text("Tap to click · hold to drag · two fingers to scroll or tap for Back")
                    .scaledFont(12).foregroundStyle(Color.ink.opacity(0.7))
                    .padding(.bottom, 16)
                    .allowsHitTesting(false)
            }
            .contentShape(shape)
            .background {
                TwoFingerScroll(
                    state: scrollState,
                    onScroll: { wheel, hscroll in remote.mouse(wheel: wheel, hscroll: hscroll) },
                    onTwoFingerTap: {
                        Haptics.light()
                        remote.key("BACK")
                    }
                )
            }
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local)
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
            .onChange(of: appsExpanded) { _ in cancelPointer() }
            .onDisappear { cancelPointer() }
            // While the Apps grid is open the page scrolls instead of moving the cursor.
            .allowsHitTesting(!androidExpanded)
            .opacity(androidExpanded ? 0.6 : 1)
    }

    private var dpadSurface: some View {
        let shape = RoundedRectangle(cornerRadius: 36, style: .continuous)
        return GeometryReader { geo in
            let size = max(180, min(420, min(geo.size.width, geo.size.height) - 12))
            GlassDpad(size: size) { remote.routedKey($0) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .glassSurface(shape)
        // Swipe anywhere on the pad to send an arrow, like the Apple TV remote.
        .simultaneousGesture(
            DragGesture(minimumDistance: 28)
                .onEnded { value in
                    let w = value.translation.width, h = value.translation.height
                    let name = abs(w) > abs(h) ? (w > 0 ? "RIGHT" : "LEFT") : (h > 0 ? "DOWN" : "UP")
                    Haptics.soft()
                    remote.routedKey(name)
                }
        )
        .allowsHitTesting(!androidExpanded)
        .opacity(androidExpanded ? 0.6 : 1)
    }

    // MARK: - Navigation and volume

    private var navRow: some View {
        GlassGroup(spacing: 10) {
            HStack(spacing: 10) {
                RemoteKeyButton(symbol: "arrow.uturn.backward", label: "Back") { remote.routedKey("BACK") }
                RemoteKeyButton(label: "Home", action: { remote.routedKey("HOME") }) { HomeGlyph() }
                // Opens the Samsung TV's own input/source menu (KEY_SOURCE) over the Samsung link. It is
                // separate from the device selector. If the link is down the status line says so.
                RemoteKeyButton(symbol: "cable.connector", label: "Sources") { remote.samsungKey(.source) }
                RemoteKeyButton(symbol: "magnifyingglass", label: "Search") { navigator.openSearch() }
                RemoteKeyButton(symbol: "keyboard", label: "Keyboard") { showKeyboard = true }
            }
        }
    }

    private var volumeBar: some View {
        GlassVolumeSlider(value: $volumeSliderValue, floorIsMute: remote.volumeCalibration.lo == 0,
                          onDragChange: { remote.volumeDragChanged($0) })
            .onChange(of: volumeSliderValue) { newValue in
                // A value we just applied from the TV's own reading must not be sent back to it.
                if let echo = externalVolumeEcho, abs(newValue - echo) < 0.0001 {
                    externalVolumeEcho = nil
                    return
                }
                remote.setVolumeFraction(newValue)
            }
            .onChange(of: remote.tvVolumeFraction) { reading in
                guard let reading, remote.volumeSliderAcceptsExternal,
                      abs(reading - volumeSliderValue) > 0.0001 else { return }
                externalVolumeEcho = reading
                volumeSliderValue = reading
            }
    }
}
