import SwiftUI
import UIKit

/// Text entry for the TV: typed text, explicit clipboard paste, Backspace/Enter and recent history.
/// The clipboard is never read unless the person taps the system Paste button.
struct KeyboardSheet: View {
    @EnvironmentObject private var remote: RemoteModel
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var lastSent = ""        // what live typing has already forwarded to the TV
    @State private var liveDeliveryFailed = false   // virtual keyboard refused the last keystroke
    /// A late write failure already rolled `lastSent` back; later failures were queued after it.
    @State private var liveRolledBack = false
    @State private var history: [String] = KeyboardHistory.load()
    @State private var remembersHistory = KeyboardHistory.remembers()
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Live typing", isOn: $remote.liveTyping)
                        .onChange(of: remote.liveTyping) { _, _ in lastSent = text }
                    TextField(remote.liveTyping ? "Typing goes straight to the TV" : "Type here, then Send", text: $text, axis: .vertical)
                        .lineLimit(1...4)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focused)
                        .submitLabel(remote.liveTyping ? .return : .send)
                        .onSubmit(send)
                        .onChange(of: text) { _, newValue in syncLive(newValue) }

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
                    if remote.liveTyping && liveDeliveryFailed {
                        Text("Live typing is on, but the TV keyboard isn't ready (\(remote.connected ? "helper not running" : "not connected")). Typed text is held and sent with your next edit once it's ready.")
                            .foregroundStyle(.orange)
                    } else {
                        Text(remote.liveTyping
                             ? "Each key is sent as you type, through the virtual keyboard. Return presses Enter on the TV. Plain ASCII only."
                             : "Android can only type plain ASCII characters over ADB.")
                    }
                }

                Section {
                    Toggle("Remember sent text", isOn: $remembersHistory)
                        .onChange(of: remembersHistory) { _, on in
                            KeyboardHistory.setRemembers(on)
                            if !on { history = [] }
                        }
                    ForEach(history, id: \.self) { item in
                        Button { text = item } label: {
                            Text(item).lineLimit(1).foregroundStyle(.primary)
                        }
                    }
                    .onDelete { offsets in
                        history.remove(atOffsets: offsets)
                        KeyboardHistory.save(history)
                    }
                    if !history.isEmpty {
                        Button("Clear history", role: .destructive) {
                            history = []
                            KeyboardHistory.save(history)
                        }
                    }
                } header: {
                    Text("Recent")
                } footer: {
                    Text(remembersHistory
                         ? "The last \(KeyboardHistory.limit) texts you Send are kept on this iPhone. Turn this off before typing passwords."
                         : "Sent text isn't kept. Live typing is never kept.")
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
        .themedSheet()
    }

    /// Forwards the difference between what the TV has received and the field's new contents, in
    /// steps the keyboard accepts whole (BUG-019: long pastes are split, never cut off).
    /// Delivery failure never touches the Live typing toggle (that is the user's choice). On failure
    /// `lastSent` stays at what was delivered, so the next edit retries the undelivered difference.
    private func syncLive(_ newValue: String) {
        guard remote.liveTyping else { lastSent = newValue; liveDeliveryFailed = false; return }
        var sent = lastSent
        var steps = 0
        while sent != newValue, steps < LiveTypingDiff.maxStepsPerEdit {
            steps += 1
            let step = LiveTypingDiff.step(from: sent, to: newValue)
            let baseline = sent
            let accepted = remote.typeLive(step.added, backspaces: step.backspaces) {
                liveWriteFailed(baseline: baseline)
            }
            guard accepted else {
                lastSent = sent
                liveDeliveryFailed = true
                return
            }
            // The last step reaches the field's contents (as the single-write path always did).
            sent = step.partial ? step.delivered : newValue
        }
        lastSent = sent
        liveDeliveryFailed = false
        liveRolledBack = false
    }

    /// BUG-020: a write the keyboard accepted but could not deliver. The TV never got it, so the
    /// next edit re-sends from `baseline`. Only the first failure rolls back: anything queued after it
    /// was built on top of it.
    private func liveWriteFailed(baseline: String) {
        if !liveRolledBack {
            lastSent = baseline
            liveRolledBack = true
        }
        liveDeliveryFailed = true
    }

    private func send() {
        if remote.liveTyping {
            remote.key("OK")        // Enter
            lastSent = ""
            liveRolledBack = true   // failures from before Enter must not roll the new line back
            text = ""
            return
        }
        guard !text.isEmpty else { return }
        remote.sendText(text)
        history = KeyboardHistory.recording(text, in: history)
        KeyboardHistory.save(history)
        text = ""
    }
}

/// Recent sent texts (SEC-002). Kept only on this iPhone and only while "Remember sent text" is on;
/// turning it off deletes what was stored. Live typing is never recorded.
enum KeyboardHistory {
    static let itemsKey = "glassRemote.textHistory"
    static let rememberKey = "glassRemote.rememberTextHistory"
    static let limit = 8

    /// On by default, as before the toggle existed.
    static func remembers(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: rememberKey) as? Bool ?? true
    }

    static func setRemembers(_ on: Bool, _ defaults: UserDefaults = .standard) {
        defaults.set(on, forKey: rememberKey)
        if !on { defaults.removeObject(forKey: itemsKey) }
    }

    static func load(_ defaults: UserDefaults = .standard) -> [String] {
        remembers(defaults) ? (defaults.stringArray(forKey: itemsKey) ?? []) : []
    }

    static func save(_ items: [String], _ defaults: UserDefaults = .standard) {
        if remembers(defaults), !items.isEmpty {
            defaults.set(items, forKey: itemsKey)
        } else {
            defaults.removeObject(forKey: itemsKey)
        }
    }

    /// Most recent first, no duplicates, at most `limit`. Empty when remembering is off.
    static func recording(_ text: String, in items: [String], remembering: Bool = KeyboardHistory.remembers()) -> [String] {
        guard remembering else { return [] }
        var result = items.filter { $0 != text }
        result.insert(text, at: 0)
        return Array(result.prefix(limit))
    }
}

extension RemoteModel {
    /// `typeLive` that also reports a write that fails after the keyboard accepted it (BUG-020).
    func typeLive(_ text: String, backspaces: Int, onUndelivered: @escaping @MainActor () -> Void) -> Bool {
        guard connected else { return false }
        return keyboard.type(text, backspaces: backspaces, onWriteFailure: onUndelivered)
    }
}

/// Pure difference between what the TV already has and the field's new contents.
enum LiveTypingDiff {
    static func plan(from lastSent: String, to newValue: String) -> (backspaces: Int, added: String) {
        let common = newValue.commonPrefix(with: lastSent)
        let removed = lastSent.dropFirst(common.count)
        let backspaces = removed.filter { VirtualKeyboard.hid(for: $0) != nil }.count
        return (backspaces, String(newValue.dropFirst(common.count)))
    }

    /// One keyboard write's worth of an edit. `delivered` is what the TV holds once it lands.
    struct Step: Equatable {
        let backspaces: Int
        let added: String
        let delivered: String
        /// More steps are needed to reach the field's contents.
        let partial: Bool
    }

    /// Bounds one edit to 50 writes (20 000 characters); the rest follows with the next edit.
    static let maxStepsPerEdit = 50

    /// The next write towards `newValue`, never more than `limit` backspaces or characters, so
    /// `VirtualKeyboard.type` never cuts anything off. Deletions go first.
    static func step(from lastSent: String, to newValue: String,
                     limit: Int = VirtualKeyboard.liveTypingLimit) -> Step {
        let cap = max(limit, 1)
        let common = newValue.commonPrefix(with: lastSent)
        let diff = Self.plan(from: lastSent, to: newValue)
        if diff.backspaces > cap {
            // Delete `limit` typeable characters from the end; untypeable ones never reached the TV.
            var kept = Substring(lastSent)
            var remaining = kept.count
            var deleted = 0
            while remaining > common.count, let last = kept.last {
                let typeable = VirtualKeyboard.hid(for: last) != nil
                if typeable && deleted == cap { break }
                if typeable { deleted += 1 }
                kept.removeLast()
                remaining -= 1
            }
            return Step(backspaces: deleted, added: "", delivered: String(kept), partial: true)
        }
        let added = String(diff.added.prefix(cap))
        let partial = diff.added.count > cap
        return Step(backspaces: diff.backspaces, added: added, delivered: common + added, partial: partial)
    }
}
