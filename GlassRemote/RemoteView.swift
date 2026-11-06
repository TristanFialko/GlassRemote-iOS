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
    @State private var showPlayer = false
    @State private var showDeviceInfo = false
    @State private var showThemes = false
    @ObservedObject private var favourites = AppFavourites.shared
    @State private var volumeSliderValue: Double = 0.5
    @State private var externalVolumeEcho: Double?

    /// The Apps grid belongs to the Android remote only. Everything that reacts to it (page height,
    /// scrolling, pad dimming) reads this, so the Samsung remote never inherits the expanded layout.
    /// `appsExpanded` itself is kept, so the state survives a round trip to Samsung and back.
    private var androidExpanded: Bool { appsExpanded && remote.target == .android }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 9), count: 3)

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 8) {
                    header
                    deviceSelector
                    if remote.target == .samsung {
                        // Samsung mode: a permanent trackpad and a short key set replace the Android controls.
                        SamsungRemotePanel()
                    } else {
                        appsSection
                        nowPlaying
                        modeRow
                        // The pad is the point of this page: it takes every spare point and never shrinks
                        // below a comfortable size, while the buttons around it keep their full size.
                        controlSurface
                            .frame(minHeight: 230, maxHeight: androidExpanded ? 230 : CGFloat.infinity)
                            .layoutPriority(1)
                        navRow
                    }
                    volumeBar
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 8)
                .frame(height: androidExpanded ? nil : proxy.size.height)
            }
            // The page only scrolls while the Apps grid pushes content below the fold.
            .scrollDisabled(!androidExpanded)
        }
        .background { backdrop }
        .themedSheet()
        // Text follows Dynamic Type, capped so the fixed remote layout keeps fitting.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .sheet(isPresented: $remote.showConnection) { ConnectionSheet().environmentObject(remote) }
        .sheet(isPresented: $showThemes) { ThemePickerSheet() }
        .sheet(isPresented: $showKeyboard) { KeyboardSheet().environmentObject(remote) }
        .sheet(item: $screenshotItem) { item in ScreenshotSheet(item: item) }
        .sheet(isPresented: $showDeviceInfo) { DeviceInfoSheet().environmentObject(remote) }
        .sheet(isPresented: $showPlayer) {
            NowPlayingSheet().environmentObject(remote)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
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
        case .off: return Color.ink.opacity(0.35)
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

    // MARK: - Now playing

    private var nowPlaying: some View {
        let media = remote.media
        let app = remote.apps.first(where: { $0.package == media.package })

        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.black.opacity(0.75))
                if let app {
                    // Stremio uses a transparent, border-free asset so it sits on the card with no second frame.
                    Image(app.asset == "stremio" ? "stremio_nowplaying" : "\(app.asset)_dark").resizable().scaledToFit().padding(app.asset == "stremio" ? 9 : 3)
                } else {
                    Image(systemName: media.isActive ? "play.rectangle" : "tv")
                        .scaledFont(20).foregroundStyle(Color.ink.opacity(0.55))
                }
            }
            .frame(width: 42, height: 42)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.ink.opacity(0.18)))

            VStack(alignment: .leading, spacing: 3) {
                Text(media.isActive ? (media.title.isEmpty ? (app?.name ?? "Playing") : media.title) : "Nothing playing")
                    .scaledFont(14, .semibold)
                    .lineLimit(1)
                    .truncationMode(.tail)
                subtitle(media: media, app: app)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Previous/Next are preferred where the session offers them; otherwise Rewind/Fast-forward.
            // A control the session does not advertise is shown dimmed and disabled.
            mediaButton(
                icon: media.canPrevious ? "backward.end.fill" : "backward.fill",
                label: media.canPrevious ? "Previous" : "Rewind",
                enabled: media.canPrevious || media.canRewind
            ) { remote.sendMedia(media.canPrevious ? .previous : .rewind) }

            mediaButton(
                icon: media.isPlaying ? "pause.fill" : "play.fill",
                label: media.isPlaying ? "Pause" : "Play",
                enabled: media.isActive && media.canPlayPause && !remote.mediaCommandPending,
                prominent: true
            ) { remote.sendMedia(media.isPlaying ? .pause : .play) }

            mediaButton(
                icon: media.canNext ? "forward.end.fill" : "forward.fill",
                label: media.canNext ? "Next" : "Fast forward",
                enabled: media.canNext || media.canFastForward
            ) { remote.sendMedia(media.canNext ? .next : .fastForward) }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        // The whole card opens the expanded player. The tap target sits BEHIND the content, so the
        // Previous / Play-Pause / Next buttons (drawn on top) receive their own taps and never reach it.
        .background {
            Color.clear
                .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .onTapGesture { if media.isActive { showPlayer = true } }
        }
        .glassSurface(RoundedRectangle(cornerRadius: 28, style: .continuous), elevated: true)
        .accessibilityAction(named: "Open player") { if media.isActive { showPlayer = true } }
    }

    @ViewBuilder
    private func subtitle(media: MediaState, app: TVApp?) -> some View {
        let name = app?.name ?? (media.package.split(separator: ".").last.map(String.init) ?? "")
        if media.isActive {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let position = MediaState.format(media.position(at: context.date))
                Text(media.positionMs > 0 || media.isPlaying ? "\(name) · \(position)" : name)
                    .scaledFont(12).foregroundStyle(Color.ink.opacity(0.65)).lineLimit(1)
            }
        } else {
            Text(remote.connected ? "Start something on the TV" : "Not connected")
                .scaledFont(12).foregroundStyle(Color.ink.opacity(0.55)).lineLimit(1)
        }
    }

    private func mediaButton(icon: String, label: String, enabled: Bool, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .scaledFont(15, .semibold)
                .foregroundStyle(Color.ink)
                .frame(width: 44, height: 44)   // touch target unchanged
                .glassSurface(Circle(), interactive: enabled, elevated: prominent)
        }
        .buttonStyle(PressStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityLabel(label)
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
            let size = max(170, min(340, min(geo.size.width, geo.size.height) - 16))
            ZStack {
                Color.clear.glassSurface(Circle(), elevated: true)
                    .frame(width: size, height: size)
                    // Depth: soft top light falling to a darker lower edge.
                    .overlay(Circle().fill(RadialGradient(colors: [Color.white.opacity(0.10), .clear],
                                                          center: .init(x: 0.5, y: 0.12), startRadius: 4, endRadius: size * 0.7))
                        .allowsHitTesting(false))
                    // Fine rim highlight (bright on top, dark underneath) plus a hairline inner edge.
                    .overlay(Circle().strokeBorder(LinearGradient(colors: [Color.white.opacity(0.34), Color.white.opacity(0.06), Color.black.opacity(0.5)],
                                                                  startPoint: .top, endPoint: .bottom), lineWidth: 1.2))
                    .overlay(Circle().stroke(Color.black.opacity(0.45), lineWidth: 0.8).padding(1.8))
                    // Directional separation: four hairline seams on the diagonals, stopping short of the centre.
                    .overlay(DpadSeams().stroke(Color.ink.opacity(0.12), lineWidth: 0.8).padding(size * 0.06)
                        .allowsHitTesting(false))
                    .overlay(Circle().stroke(Color.ink.opacity(0.12), lineWidth: 0.8).frame(width: size * 0.36, height: size * 0.36)
                        .allowsHitTesting(false))
                    .shadow(color: .black.opacity(0.5), radius: 14, y: 8)
                VStack(spacing: 0) {
                    HStack(spacing: 0) { Color.clear; dpadKey("chevron.up", "UP", "Up"); Color.clear }
                    HStack(spacing: 0) {
                        dpadKey("chevron.left", "LEFT", "Left")
                        dpadKey("circle.fill", "OK", "Select", ok: true)
                        dpadKey("chevron.right", "RIGHT", "Right")
                    }
                    HStack(spacing: 0) { Color.clear; dpadKey("chevron.down", "DOWN", "Down"); Color.clear }
                }
                .padding(10)
                .frame(width: size, height: size)
            }
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

    private func dpadKey(_ icon: String, _ key: String, _ label: String, ok: Bool = false) -> some View {
        // Tap = one press; hold = auto-repeat (arrows only, so OK never repeats into a double-select).
        RepeatKey(onFire: { remote.routedKey(key) }) {
            Image(systemName: icon)
                .scaledFont(ok ? 12 : 22, .medium)
                .foregroundStyle(Color.ink)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    if ok {
                        Color.clear.glassSurface(Circle(), interactive: true, elevated: true, accent: true).padding(6)
                            .overlay(Circle().strokeBorder(LinearGradient(colors: [Color.white.opacity(0.4), Color.white.opacity(0.05)],
                                                                          startPoint: .top, endPoint: .bottom), lineWidth: 1).padding(6))
                            .shadow(color: .black.opacity(0.4), radius: 5, y: 3)
                    }
                }
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { remote.routedKey(key) }
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

/// Four short diagonal seams between the D-pad's directional areas (visual only: hit areas are unchanged).
private struct DpadSeams: Shape {
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        var p = Path()
        for angle in [45.0, 135.0, 225.0, 315.0] {
            let a = angle * .pi / 180
            p.move(to: CGPoint(x: c.x + cos(a) * r * 0.36, y: c.y + sin(a) * r * 0.36))
            p.addLine(to: CGPoint(x: c.x + cos(a) * r * 0.98, y: c.y + sin(a) * r * 0.98))
        }
        return p
    }
}
