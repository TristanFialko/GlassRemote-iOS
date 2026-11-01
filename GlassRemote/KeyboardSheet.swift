import SwiftUI
import UIKit

/// Text entry for the TV: typed text, explicit clipboard paste, Backspace/Enter and recent history.
/// The clipboard is never read unless the person taps the system Paste button.
struct KeyboardSheet: View {
    @EnvironmentObject private var remote: RemoteModel
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var history: [String] = KeyboardSheet.loadHistory()
    @FocusState private var focused: Bool

    private static let historyKey = "glassRemote.textHistory"
    private static let historyLimit = 8

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Type here, then Send", text: $text, axis: .vertical)
                        .lineLimit(1...4)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focused)
                        .submitLabel(.send)
                        .onSubmit(send)

                    HStack(spacing: 10) {
                        PasteButton(payloadType: String.self) { strings in
                            text += strings.joined(separator: " ")
                        }
                        .labelStyle(.titleAndIcon)

                        Spacer()

                        Button { remote.androidKey(67) } label: {
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
                        .disabled(text.isEmpty)
                    }
                } footer: {
                    Text("Android can only type plain ASCII characters over ADB.")
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
            .background(Color.black)
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

    private func send() {
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
