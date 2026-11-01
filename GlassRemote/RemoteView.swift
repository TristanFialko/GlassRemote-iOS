import SwiftUI
import UIKit

/// Plain storage for the last drag point. Intentionally not observable.
final class PointerBox { var last: CGPoint? }

struct RemoteView: View {
    @EnvironmentObject private var remote: RemoteModel
    @ObservedObject private var quick = QuickActionStore.shared

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
    @State private var showQuickEditor = false
    @State private var pendingPower: PowerAction?
    @State private var didAutoConnect = false
    @State private var showPlayer = false
    @State private var volumeSliderValue: Double = 0.5
    @State private var volumeLastCommandValue: Double = 0.5

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 9), count: 3)

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 10) {
                    header
                    appsSection
                    nowPlaying
                    quickActionsRow
                    ModeSelector(isMouse: $remote.isTrackpad)
                    controlSurface
                        .frame(minHeight: 150, maxHeight: appsExpanded ? 210 : CGFloat.infinity)
                    navRow
                    volumeBar
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 8)
                .frame(height: appsExpanded ? nil : proxy.size.height)
            }
            // The page only scrolls while the Apps grid pushes content below the fold.
            .scrollDisabled(!appsExpanded)
        }
        .background { backdrop }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $remote.showConnection) { ConnectionSheet().environmentObject(remote) }
        .sheet(isPresented: $showKeyboard) { KeyboardSheet().environmentObject(remote) }
        .sheet(isPresented: $showQuickEditor) { QuickActionEditor(store: quick) }
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
            if !remote.connected && !remote.requiresUserReconnect { remote.connect() }
        }
    }

    // MARK: - Backdrop

    private var backdrop: some View { AmbientBackdrop() }

    // MARK: - Header

    private var statusLabel: String {
        if remote.connected { return "Connected" }
        if remote.status.hasPrefix("Connecting") || remote.status.contains("reconnect") { return "Connecting…" }
        return "Offline"
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button { remote.showConnection = true } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 44, height: 44)
                    .glassSurface(Circle(), interactive: true)
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Connection settings")

            Spacer(minLength: 0)

            Button { if !remote.connected { remote.connect() } } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(remote.connected ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                        .shadow(color: (remote.connected ? Color.green : Color.orange).opacity(0.35), radius: 2)
                    Text(statusLabel).font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(Color.white.opacity(0.85))
                .padding(.horizontal, 16)
                .frame(height: 36)
                .glassSurface(Capsule(), interactive: true)
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel(remote.connected ? "Connected" : "Reconnect")

            Spacer(minLength: 0)

            Menu {
                Button { pendingPower = .standby } label: { Label("Standby", systemImage: "moon.zzz") }
                Button { remote.wake() } label: { Label("Wake", systemImage: "sun.max") }
                Button { pendingPower = .restartLauncher } label: { Label("Restart launcher", systemImage: "arrow.clockwise") }
                Button(role: .destructive) { pendingPower = .restartBox } label: { Label("Restart TV box", systemImage: "power") }
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 44, height: 44)
                    .glassSurface(Circle(), interactive: true)
            }
            .accessibilityLabel("Power and device")
        }
        .foregroundStyle(.white)
    }

    private func perform(_ action: PowerAction) {
        switch action {
        case .standby: remote.standby()
        case .restartLauncher: remote.restartLauncher()
        case .restartBox: remote.restartBox()
        }
    }

    // MARK: - Apps (collapsed by default)

    private var appsSection: some View {
        VStack(spacing: 10) {
            Button {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) { appsExpanded.toggle() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "square.grid.2x2").font(.system(size: 19, weight: .medium))
                    Text("Apps").font(.system(size: 15, weight: .semibold))
                    Spacer()
                    if !appsExpanded {
                        Text("\(remote.apps.count)").font(.system(size: 13)).foregroundStyle(.white.opacity(0.65))
                    }
                    Image(systemName: appsExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .frame(height: appsExpanded ? 40 : 54)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(appsExpanded ? "Hide apps" : "Show apps")

            if appsExpanded {
                appGrid
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }
        }
        .padding(.horizontal, appsExpanded ? 8 : 0)
        .padding(.bottom, appsExpanded ? 10 : 0)
        .frame(maxWidth: .infinity)
        .glassSurface(RoundedRectangle(cornerRadius: appsExpanded ? 34 : 27, style: .continuous), interactive: !appsExpanded)
    }

    // Same artwork, order and tile construction as before; only the surrounding panel is new.
    private var appGrid: some View {
        LazyVGrid(columns: columns, spacing: 9) {
            ForEach(remote.apps) { app in
                Button {
                    remote.launch(app)
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) { appsExpanded = false }
                } label: {
                    Image("\(app.asset)_dark")
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 17, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                        }
                        .background {
                            RoundedRectangle(cornerRadius: 17, style: .continuous)
                                .fill(.ultraThinMaterial)
                        }
                        .shadow(color: .black.opacity(0.34), radius: 8, y: 4)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(1, contentMode: .fit)
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel(app.name)
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
                        .font(.system(size: 20)).foregroundStyle(.white.opacity(0.55))
                }
            }
            .frame(width: 50, height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.18)))

            VStack(alignment: .leading, spacing: 3) {
                Text(media.isActive ? (media.title.isEmpty ? (app?.name ?? "Playing") : media.title) : "Nothing playing")
                    .font(.system(size: 14, weight: .semibold))
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
            ) { remote.mediaKey(media.canPrevious ? 88 : 89) }

            mediaButton(
                icon: media.isPlaying ? "pause.fill" : "play.fill",
                label: media.isPlaying ? "Pause" : "Play",
                enabled: media.isActive && media.canPlayPause,
                prominent: true
            ) { remote.mediaKey(85) }

            mediaButton(
                icon: media.canNext ? "forward.end.fill" : "forward.fill",
                label: media.canNext ? "Next" : "Fast forward",
                enabled: media.canNext || media.canFastForward
            ) { remote.mediaKey(media.canNext ? 87 : 90) }
        }
        .padding(12)
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
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
            }
        } else {
            Text(remote.connected ? "Start something on the TV" : "Not connected")
                .font(.system(size: 12)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
        }
    }

    private func mediaButton(icon: String, label: String, enabled: Bool, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .glassSurface(Circle(), interactive: enabled, elevated: prominent)
        }
        .buttonStyle(PressStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityLabel(label)
    }

    // MARK: - Quick Actions

    private var quickActionsRow: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(quick.actions) { action in
                        Button { remote.runQuickAction(action) } label: {
                            Text(action.name)
                                .font(.system(size: 14, weight: .semibold))
                                .lineLimit(1)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)
                                .frame(height: 36)
                                .glassSurface(Capsule(), interactive: true, elevated: remote.runningQuickActionID == action.id)
                        }
                        .buttonStyle(PressStyle())
                        .opacity(remote.connected ? 1 : 0.5)
                    }
                }
            }
            Button { showQuickEditor = true } label: {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .glassSurface(Capsule(), interactive: true)
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Edit Quick Actions")
        }
        .frame(height: 36)
    }

    // MARK: - Mouse / D-pad surface

    @ViewBuilder
    private var controlSurface: some View {
        if remote.isTrackpad { mouseSurface } else { dpadSurface }
    }

    private var mouseSurface: some View {
        let shape = RoundedRectangle(cornerRadius: 36, style: .continuous)
        return Color.clear
            .glassSurface(shape, elevated: true)
            .overlay(alignment: .bottom) {
                Text("Tap to click · two fingers to scroll")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.7))
                    .padding(.bottom, 16)
                    .allowsHitTesting(false)
            }
            .contentShape(shape)
            .background {
                TwoFingerScroll(state: scrollState) { wheel, hscroll in
                    remote.mouse(wheel: wheel, hscroll: hscroll)
                }
            }
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in
                    if let previous = lastPoint {
                        let dx = Int((value.location.x - previous.x) * 2)
                        let dy = Int((value.location.y - previous.y) * 2)
                        if abs(dx) + abs(dy) > 0 && !scrollState.isActive { remote.mouse(dx: dx, dy: dy) }
                    }
                    lastPoint = value.location
                }
                .onEnded { value in
                    if abs(value.translation.width) < 8 && abs(value.translation.height) < 8 && !scrollState.suppressesClicks {
                        remote.mouse(buttons: 1); UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.045) { remote.mouse(buttons: 0) }
                    }
                    lastPoint = nil
                })
            // While the Apps grid is open the page scrolls instead of moving the cursor.
            .allowsHitTesting(!appsExpanded)
            .opacity(appsExpanded ? 0.6 : 1)
    }

    private var dpadSurface: some View {
        let shape = RoundedRectangle(cornerRadius: 36, style: .continuous)
        return GeometryReader { geo in
            let size = max(150, min(250, min(geo.size.width, geo.size.height) - 24))
            ZStack {
                Color.clear.glassSurface(Circle(), elevated: true)
                    .frame(width: size, height: size)
                    .overlay(Circle().stroke(Color.white.opacity(0.20), lineWidth: 1.5))
                    .overlay(Circle().stroke(Color.black.opacity(0.55), lineWidth: 1).padding(1.5))
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
        .allowsHitTesting(!appsExpanded)
        .opacity(appsExpanded ? 0.6 : 1)
    }

    private func dpadKey(_ icon: String, _ key: String, _ label: String, ok: Bool = false) -> some View {
        Button { remote.key(key) } label: {
            Image(systemName: icon)
                .font(.system(size: ok ? 12 : 22, weight: .medium))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    if ok { Color.clear.glassSurface(Circle(), interactive: true, elevated: true, accent: true).padding(6) }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(label)
    }

    // MARK: - Navigation and volume

    private var navRow: some View {
        HStack(spacing: 10) {
            navButton("arrow.uturn.backward", "Back") { remote.key("BACK") }
            navButton("house", "Home") { remote.key("HOME") }
            navButton("line.3.horizontal", "Menu") { remote.key("MENU") }
            navButton("keyboard", "Keyboard") { showKeyboard = true }
        }
    }

    private func navButton(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .glassSurface(Capsule(), interactive: true)
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(label)
    }

private var volumeBar: some View {
    HStack(spacing: 13) {
        Image(systemName: volumeSliderValue <= 0.02 ? "speaker" : "speaker.wave.2.fill")
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(.white.opacity(0.92))
            .frame(width: 30)
            .accessibilityHidden(true)

        Slider(value: $volumeSliderValue, in: 0...1)
            .tint(.white)
            .accessibilityLabel("Volume")
            .accessibilityHint("Drag horizontally to adjust the TV volume")
             private var volumeBar: some View {
        HStack(spacing: 13) {
            Image(systemName: volumeSliderValue <= 0.02 ? "speaker" : "speaker.wave.2.fill")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
                .frame(width: 30)
                .accessibilityHidden(true)

            Slider(value: $volumeSliderValue, in: 0...1)
                .tint(.white)
                .accessibilityLabel("Volume")
                .accessibilityHint("Drag horizontally to adjust the TV volume")
                .onChange(of: volumeSliderValue) { newValue in
                    let oldStep = Int((volumeLastCommandValue * 20).rounded())
                    let newStep = Int((newValue * 20).rounded())

                    volumeLastCommandValue = newValue

                    let difference = newStep - oldStep
                    guard difference != 0 else { return }

                    let key = difference > 0 ? "VOLUME_UP" : "VOLUME_DOWN"

                    for _ in 0..<min(abs(difference), 4) {
                        remote.volume(key)
                    }
                }
        }
        .padding(.horizontal, 18)
        .frame(height: 58)
        .glassSurface(Capsule(), interactive: true, elevated: true)
    }
}
