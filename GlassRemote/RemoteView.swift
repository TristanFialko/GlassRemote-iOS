import SwiftUI
import UIKit

private let glass = Color.white.opacity(0.065)
private let glassLine = Color.white.opacity(0.15)

struct RemoteView: View {
    @EnvironmentObject private var remote: RemoteModel
    @State private var text = ""
    @State private var lastPoint: CGPoint?
    @State private var dragging = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 9), count: 3)

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.height < 760
            let side = max(12, min(17, proxy.size.width * 0.041))
            VStack(spacing: compact ? 8 : 10) {
                header
                    .frame(height: 34)
                appGrid(compact: compact)
                textEntry
                    .frame(height: 48)
                controlPanel(compact: compact)
                    .frame(maxHeight: .infinity)
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
        LazyVGrid(columns: columns, spacing: compact ? 7 : 9) {
            ForEach(remote.apps) { app in
                Button { remote.launch(app) } label: {
                    Image("\(app.asset)_dark")
                        .resizable().scaledToFit()
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 5).padding(.vertical, 4)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(1.24, contentMode: .fit)
                        .background(LinearGradient(colors: [Color.white.opacity(0.10), Color.white.opacity(0.025)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 15))
                        .overlay(RoundedRectangle(cornerRadius: 15).stroke(glassLine, lineWidth: 1))
                        .shadow(color: .black.opacity(0.35), radius: 9, y: 5)
                }
                .buttonStyle(PressStyle())
                .disabled(remote.connected && !remote.installed.contains(app.package))
                .opacity(remote.connected && !remote.installed.contains(app.package) ? 0.28 : 1)
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

    private func sendText() { guard !text.isEmpty else { return }; remote.sendText(text); text = "" }

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
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: 23)
                .fill(LinearGradient(colors: [Color.white.opacity(0.13), Color.white.opacity(0.035)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: 23).stroke(Color.white.opacity(0.2)))
                .shadow(color: .black.opacity(0.55), radius: 14, y: 8)
                .contentShape(RoundedRectangle(cornerRadius: 23))
                .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        if let previous = lastPoint {
                            let dx = Int((value.location.x - previous.x) * 2)
                            let dy = Int((value.location.y - previous.y) * 2)
                            if abs(dx) + abs(dy) > 0 { remote.mouse(dx: dx, dy: dy) }
                        }
                        lastPoint = value.location
                        if !dragging && value.translation == .zero { }
                    }
                    .onEnded { value in
                        if abs(value.translation.width) < 8 && abs(value.translation.height) < 8 {
                            remote.mouse(buttons: 1); UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.045) { remote.mouse(buttons: 0) }
                        }
                        lastPoint = nil
                    })
                .onLongPressGesture(minimumDuration: 0.35, pressing: { pressing in
                    dragging = pressing
                    if pressing { remote.mouse(buttons: 1); UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
                    else { remote.mouse(buttons: 0) }
                }, perform: {})
        }
        .frame(height: geoTrackpadHeight)
    }

    private var geoTrackpadHeight: CGFloat { 142 }

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

private struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.95 : 1).opacity(configuration.isPressed ? 0.82 : 1).animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
