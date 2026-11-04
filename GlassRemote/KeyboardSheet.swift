import SwiftUI
import UIKit

/// Text entry for the TV: typed text, explicit clipboard paste, Backspace/Enter and recent history.
/// The clipboard is never read unless the person taps the system Paste button.
struct KeyboardSheet: View {
    @EnvironmentObject private var remote: RemoteModel
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var lastSent = ""        // what live typing has already forwarded to the TV
    @State private var history: [String] = KeyboardSheet.loadHistory()
    @FocusState private var focused: Bool

    private static let historyKey = "glassRemote.textHistory"
    private static let historyLimit = 8

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Live typing", isOn: $remote.liveTyping)
                        .onChange(of: remote.liveTyping) { _ in lastSent = text }
                    TextField(remote.liveTyping ? "Typing goes straight to the TV" : "Type here, then Send", text: $text, axis: .vertical)
                        .lineLimit(1...4)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focused)
                        .submitLabel(remote.liveTyping ? .return : .send)
                        .onSubmit(send)
                        .onChange(of: text) { newValue in syncLive(newValue) }

                    HStack(spacing: 10) {
                        PasteButton(payloadType: String.self) { strings in
                            text += strings.joined(separator: " ")
                        }
                        .labelStyle(.titleAndIcon)

                        Spacer()

                        Button {
                            // Live: editing the field sends the backspace. Otherwise delete on the TV directly.
                            if remote.liveTyping, !text.isEmpty { text.removeLast() } else { remote.androidKey(67) }
                        } label: {
                            Image(systemName: "delete.left")
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Backspace")

                        Button { remote.androidKey(66) } label: {
                            Image(systemName: "return")
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Enter")

                        Button(action: send) {
                            Label("Send", systemImage: "arrow.up.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(text.isEmpty && !remote.liveTyping)
                    }
                } footer: {
                    Text(remote.liveTyping
                         ? "Each key is sent as you type, through the virtual keyboard. Return presses Enter on the TV. Plain ASCII only."
                         : "Android can only type plain ASCII characters over ADB.")
                }

                if !history.isEmpty {
                    Section("Recent") {
                        ForEach(history, id: \.self) { item in
                            Button { text = item } label: {
                                Text(item).lineLimit(1).foregroundStyle(.primary)
                            }
                        }
                        .onDelete { offsets in
                            history.remove(atOffsets: offsets)
                            Self.saveHistory(history)
                        }
                        Button("Clear history", role: .destructive) {
                            history = []
                            Self.saveHistory(history)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background { AmbientBackdrop() }
            .navigationTitle("Keyboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }

    /// Forwards the difference between what the TV has received and the field's new contents.
    private func syncLive(_ newValue: String) {
        guard remote.liveTyping else { lastSent = newValue; return }
        guard newValue != lastSent else { return }
        let common = newValue.commonPrefix(with: lastSent)
        let removed = lastSent.dropFirst(common.count)
        let backspaces = removed.filter { VirtualKeyboard.hid(for: $0) != nil }.count
        let added = String(newValue.dropFirst(common.count))
        if remote.typeLive(added, backspaces: backspaces) {
            lastSent = newValue
        } else {
            // Virtual keyboard not ready: fall back to the normal Send flow.
            remote.liveTyping = false
            lastSent = newValue
        }
    }

    private func send() {
        if remote.liveTyping {
            remote.key("OK")        // Enter
            lastSent = ""
            text = ""
            return
        }
        guard !text.isEmpty else { return }
        remote.sendText(text)
        history.removeAll { $0 == text }
        history.insert(text, at: 0)
        history = Array(history.prefix(Self.historyLimit))
        Self.saveHistory(history)
        text = ""
    }

    private static func loadHistory() -> [String] {
        UserDefaults.standard.stringArray(forKey: historyKey) ?? []
    }

    private static func saveHistory(_ items: [String]) {
        UserDefaults.standard.set(items, forKey: historyKey)
    }
}
