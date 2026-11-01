import SwiftUI
import UIKit

private let glass = Color.white.opacity(0.065)
private let glassLine = Color.white.opacity(0.15)

struct RemoteView: View {
    @EnvironmentObject private var remote: RemoteModel
    @State private var text = ""

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 9), count: 3)

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.height < 760
            let side = max(12, min(17, proxy.size.width * 0.041))
            VStack(spacing: compact ? 8 : 10) {
                header.frame(height: 34)
                appGrid(compact: compact)
                textEntry.frame(height: 48)
                controlPanel(compact: compact).frame(maxHeight: .infinity)
            }
            .padding(.horizontal, side)
            .padding(.top, 7)
            .padding(.bottom, 5)
            .frame(maxWidth: 560, maxHeight: .infinity)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.ignoresSafeArea())
            .background {
                RadialGradient(colors: [Color.white.opacity(0.055), .clear], center: .top, startRadius: 0, endRadius: 380).ignoresSafeArea()
            }
            .sheet(isPresented: $remote.showConnection) { connectionSheet }
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack {
            Button { remote.showConnection = true } label: {
                Image(systemName: "slider.horizontal.3").font(.system(size: 17, weight: .medium))
                    .frame(width: 38, height: 38).background(glass, in: Circle()).overlay(Circle().stroke(glassLine))
            }
            Spacer()
            Circle().fill(remote.connected ? Color.green : Color.orange).frame(width: 7, height: 7)
                .shadow(color: (remote.connected ? Color.green : Color.orange).opacity(0.5), radius: 5)
            Button { remote.connect() } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 16, weight: .medium))
                    .frame(width: 38, height: 38).background(glass, in: Circle()).overlay(Circle().stroke(glassLine))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 2)
    }

    private func appGrid(compact: Bool) -> some View {
        LazyVGrid(columns: columns, spacing: compact ? 8 : 10) {
            ForEach(remote.apps) { app in
                Button { remote.launch(app) } label: {
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
        .padding(10)
        .background(panelBackground)
    }

    private var textEntry: some View {
        HStack(spacing: 8) {
            TextField("", text: $text).textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.send)
                .onSubmit(sendText).padding(.horizontal, 13).frame(height: 42)
                .background(Color.black.opacity(0.32), in: RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.white.opacity(0.11)))
            Button(action: sendText) {
                Image(systemName: "arrow.right").font(.system(size: 17, weight: .semibold)).frame(width: 42, height: 42)
                    .background(glass, in: RoundedRectangle(cornerRadius: 13)).overlay(RoundedRectangle(cornerRadius: 13).stroke(glassLine))
            }
        }
        .padding(7).background(panelBackground)
    }

    private func sendText() {
        guard !text.isEmpty else { return }
        remote.sendText(text)
        text = ""
    }

    private func controlPanel(compact: Bool) -> some View {
        VStack(spacing: compact ? 8 : 10) {
            HStack(spacing: 4) {
                modeButton("Trackpad", icon: "rectangle.dashed", selected: remote.isTrackpad) { remote.isTrackpad = true }
                modeButton("D-pad", icon: "arrow.up.left.and.arrow.down.right", selected: !remote.isTrackpad) { remote.isTrackpad = false }
            }
            .padding(4).background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(glassLine))

            if remote.isTrackpad {
                trackpad
                    .frame(maxWidth: 330).frame(maxWidth: .infinity)
                    .frame(maxHeight: .infinity)
            } else {
                dpad.frame(maxHeight: .infinity)
            }

            HStack(spacing: 9) {
                actionButton("arrow.uturn.backward", key: "BACK")
                actionButton("house", key: "HOME")
                actionButton("line.3.horizontal", key: "MENU")
            }
            HStack(spacing: 9) {
                actionButton("speaker.minus", key: "VOLUME_DOWN")
                actionButton("speaker.slash", key: "MUTE")
                actionButton("speaker.plus", key: "VOLUME_UP")
            }
        }
        .padding(11)
        .background(panelBackground)
    }

    private var trackpad: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 23)
                .fill(LinearGradient(colors: [Color.white.opacity(0.13), Color.white.opacity(0.035)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: 23).stroke(Color.white.opacity(0.2)))
                .shadow(color: .black.opacity(0.55), radius: 14, y: 8)

            TrackpadTouchSurface(
                onMove: { dx, dy in remote.mouse(dx: dx, dy: dy) },
                onScroll: { vertical, horizontal in remote.mouse(wheel: vertical, hscroll: horizontal) },
                onClick: {
                    remote.mouse(buttons: 1)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
                        remote.mouse(buttons: 0)
                    }
                },
                onDragState: { isDragging in
                    remote.mouse(buttons: isDragging ? 1 : 0)
                    if isDragging {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 23))
        }
        .frame(height: 142)
    }

    private var dpad: some View {
        VStack(spacing: 6) {
            dpadKey("chevron.up", "UP")
            HStack(spacing: 6) {
                dpadKey("chevron.left", "LEFT")
                dpadKey("circle.fill", "OK")
                dpadKey("chevron.right", "RIGHT")
            }
            dpadKey("chevron.down", "DOWN")
        }
        .frame(maxWidth: 230).frame(maxWidth: .infinity)
    }

    private func dpadKey(_ icon: String, _ key: String) -> some View {
        Button { remote.key(key) } label: {
            Image(systemName: icon).font(.system(size: key == "OK" ? 12 : 19, weight: .medium))
                .frame(maxWidth: .infinity).frame(height: 43).background(glass, in: RoundedRectangle(cornerRadius: 13)).overlay(RoundedRectangle(cornerRadius: 13).stroke(glassLine))
        }.buttonStyle(PressStyle())
    }

    private func modeButton(_ title: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 17, weight: .medium)).foregroundStyle(selected ? .white : .white.opacity(0.48))
                .frame(width: 51, height: 35).background(selected ? Color.white.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain).accessibilityLabel(title)
    }

    private func actionButton(_ icon: String, key: String) -> some View {
        Button { remote.key(key) } label: {
            Image(systemName: icon).font(.system(size: 18, weight: .medium)).frame(maxWidth: .infinity).frame(height: 43)
                .background(glass, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(glassLine))
        }.buttonStyle(PressStyle()).accessibilityLabel(key)
    }

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 23).fill(LinearGradient(colors: [Color.white.opacity(0.095), Color.white.opacity(0.025)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(RoundedRectangle(cornerRadius: 23).stroke(Color.white.opacity(0.14)))
            .shadow(color: .black.opacity(0.6), radius: 16, y: 8)
    }

    private var connectionSheet: some View {
        NavigationStack {
            Form {
                Section("Android TV") {
                    TextField("IP address", text: $remote.host).keyboardType(.numbersAndPunctuation).textInputAutocapitalization(.never)
                    TextField("ADB port", text: $remote.port).keyboardType(.numberPad)
                    Button(remote.connected ? "Disconnect" : "Connect directly") {
                        if remote.connected { remote.disconnect() } else { remote.connect() }
                    }
                }
                Section("Status") { Text(remote.status).font(.footnote).textSelection(.enabled) }
                Section { Text("The first connection may show an ADB authorization prompt on the TV. Approve the Glass Remote host key. Keep the TV and iPhone on the same trusted Wi-Fi network.").font(.footnote).foregroundStyle(.secondary) }
            }
            .scrollContentBackground(.hidden).background(Color.black)
            .navigationTitle("Connection").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { remote.showConnection = false } } }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }
}

private struct TrackpadTouchSurface: UIViewRepresentable {
    let onMove: (Int, Int) -> Void
    let onScroll: (Int, Int) -> Void
    let onClick: () -> Void
    let onDragState: (Bool) -> Void

    func makeUIView(context: Context) -> TouchView {
        let view = TouchView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = true
        view.onMove = onMove
        view.onScroll = onScroll
        view.onClick = onClick
        view.onDragState = onDragState
        return view
    }

    func updateUIView(_ uiView: TouchView, context: Context) {
        uiView.onMove = onMove
        uiView.onScroll = onScroll
        uiView.onClick = onClick
        uiView.onDragState = onDragState
    }

    final class TouchView: UIView {
        var onMove: ((Int, Int) -> Void)?
        var onScroll: ((Int, Int) -> Void)?
        var onClick: (() -> Void)?
        var onDragState: ((Bool) -> Void)?

        private var previousCenter: CGPoint?
        private var startCenter: CGPoint?
        private var previousTouchCount = 0
        private var movedDistance: CGFloat = 0
        private var dragging = false
        private var touchToken = 0
        private var scrollRemainderX: CGFloat = 0
        private var scrollRemainderY: CGFloat = 0

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesBegan(touches, with: event)
            let active = activeTouches(event)
            previousTouchCount = active.count
            let center = centroid(active)
            previousCenter = center
            startCenter = center
            movedDistance = 0
            scrollRemainderX = 0
            scrollRemainderY = 0
            touchToken += 1

            if active.count == 1 {
                let token = touchToken
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) { [weak self] in
                    guard let self,
                          self.touchToken == token,
                          self.previousTouchCount == 1,
                          self.movedDistance < 7,
                          !self.dragging else { return }
                    self.dragging = true
                    self.onDragState?(true)
                }
            }
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesMoved(touches, with: event)
            let active = activeTouches(event)
            guard !active.isEmpty else { return }
            let center = centroid(active)

            guard let previousCenter else {
                self.previousCenter = center
                return
            }

            if active.count != previousTouchCount {
                previousTouchCount = active.count
                self.previousCenter = center
                startCenter = center
                movedDistance = 0
                return
            }

            let dx = center.x - previousCenter.x
            let dy = center.y - previousCenter.y
            movedDistance += abs(dx) + abs(dy)

            if active.count == 1 {
                if abs(dx) + abs(dy) >= 0.5 {
                    onMove?(Int(dx * 2.0), Int(dy * 2.0))
                }
            } else {
                // Two-finger pan: vertical and horizontal wheel channels.
                scrollRemainderY += -dy * 1.4
                scrollRemainderX += dx * 1.4
                let vertical = Int(scrollRemainderY)
                let horizontal = Int(scrollRemainderX)
                if vertical != 0 || horizontal != 0 {
                    onScroll?(vertical, horizontal)
                    scrollRemainderY -= CGFloat(vertical)
                    scrollRemainderX -= CGFloat(horizontal)
                }
            }

            self.previousCenter = center
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            finishTouches(event)
            super.touchesEnded(touches, with: event)
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            if dragging {
                dragging = false
                onDragState?(false)
            }
            resetTouchState()
            super.touchesCancelled(touches, with: event)
        }

        private func finishTouches(_ event: UIEvent?) {
            let remaining = activeTouches(event)
            if remaining.isEmpty {
                if dragging {
                    dragging = false
                    onDragState?(false)
                } else if previousTouchCount == 1, movedDistance < 7 {
                    onClick?()
                }
                resetTouchState()
            } else {
                previousTouchCount = remaining.count
                previousCenter = centroid(remaining)
                startCenter = previousCenter
            }
        }

        private func resetTouchState() {
            touchToken += 1
            previousCenter = nil
            startCenter = nil
            previousTouchCount = 0
            movedDistance = 0
            scrollRemainderX = 0
            scrollRemainderY = 0
        }

        private func activeTouches(_ event: UIEvent?) -> [UITouch] {
            (event?.allTouches ?? [])
                .filter { $0.view === self && $0.phase != .ended && $0.phase != .cancelled }
        }

        private func centroid(_ touches: [UITouch]) -> CGPoint {
            guard !touches.isEmpty else { return .zero }
            let points = touches.map { $0.location(in: self) }
            let x = points.reduce(CGFloat.zero) { $0 + $1.x } / CGFloat(points.count)
            let y = points.reduce(CGFloat.zero) { $0 + $1.y } / CGFloat(points.count)
            return CGPoint(x: x, y: y)
        }
    }
}

private struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.95 : 1).opacity(configuration.isPressed ? 0.82 : 1).animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
