import SwiftUI
import UIKit

/// Connect / disconnect the Nuvio account with Nuvio's own device-link flow: the sheet shows a code and a
/// link to nuvio.tv, the user approves there, and this app receives a session. No password is ever
/// typed into or sent from this app. Only the session tokens are stored (iOS Keychain).
struct NuvioAccountSheet: View {
    @ObservedObject private var account = NuvioAccount.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: "person.crop.circle").scaledFont(46, .light).foregroundStyle(Color.ink.opacity(0.7)).padding(.top, 28)
                Text("Nuvio account").scaledFont(22, .bold)
                if account.state == .signedIn { signedIn } else { signedOut }
            }
            .padding(.horizontal, 24).padding(.bottom, 24)
        }
        .foregroundStyle(Color.ink)
        .background { AmbientBackdrop() }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .themedSheet()
        .onDisappear { if account.state != .signedIn { account.cancelLink() } }
    }

    // MARK: Signed out / linking

    @ViewBuilder
    private var signedOut: some View {
        VStack(spacing: 14) {
            if account.state == .expired {
                Label("Your session expired. Sign in again.", systemImage: "exclamationmark.triangle").scaledFont(13, .semibold).foregroundStyle(.orange)
            }
            switch account.linkPhase {
            case .idle: intro
            case .starting:
                ProgressView().tint(Color.ink).padding(.top, 8)
                Text("Contacting Nuvio…").scaledFont(13).foregroundStyle(Color.inkAlpha(0.65))
            case .waiting(let code, let url, let completing): waiting(code: code, url: url, completing: completing)
            case .failed(let message):
                Text(message).scaledFont(13).foregroundStyle(.orange).multilineTextAlignment(.center)
                startButton("Try again")
            }
            privacy
        }
    }

    private var intro: some View {
        VStack(spacing: 14) {
            Text("Shows your Continue Watching and watch history from your Nuvio account. Read-only: this app never changes your Nuvio data.")
                .scaledFont(13).foregroundStyle(Color.ink.opacity(0.7)).multilineTextAlignment(.center)
            startButton("Sign in with Nuvio")
        }
    }

    private func startButton(_ title: String) -> some View {
        Button { account.startLink() } label: {
            Text(title).scaledFont(16, .semibold).frame(maxWidth: .infinity).frame(height: 52).glassBar(Capsule())
        }
        .buttonStyle(PressStyle())
    }

    private func waiting(code: String, url: URL, completing: Bool) -> some View {
        VStack(spacing: 14) {
            Text("1. Open the Nuvio link page and sign in if asked.\n2. Check that the code matches, then approve.")
                .scaledFont(13).foregroundStyle(Color.ink.opacity(0.75)).multilineTextAlignment(.center)
            Text(code).tracking(4).monospacedDigit().scaledFont(38, .bold)
                .frame(maxWidth: .infinity).padding(.vertical, 18)
                .glassSurface(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .accessibilityLabel("Sign-in code \(code.map(String.init).joined(separator: " "))")
            Button { openURL(url) } label: {
                Label("Open nuvio.tv", systemImage: "safari").scaledFont(16, .semibold).frame(maxWidth: .infinity).frame(height: 52).glassBar(Capsule())
            }.buttonStyle(PressStyle())
            Button { UIPasteboard.general.string = code } label: {
                Label("Copy code", systemImage: "doc.on.doc").scaledFont(14, .semibold).frame(maxWidth: .infinity).frame(height: 44).glassSurface(Capsule(), interactive: true)
            }.buttonStyle(PressStyle())
            HStack(spacing: 8) {
                ProgressView().tint(Color.ink)
                Text(completing ? "Approved. Finishing sign-in…" : "Waiting for approval…").scaledFont(13).foregroundStyle(Color.inkAlpha(0.7))
            }
            Button("Cancel") { account.cancelLink() }.scaledFont(14, .semibold).foregroundStyle(Color.inkAlpha(0.7))
        }
    }

    private var privacy: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Uses Nuvio's own device-link sign-in. Your Nuvio password is never entered here.", systemImage: "lock.shield")
            Label("Only Nuvio's session tokens are kept, in the iOS Keychain on this iPhone.", systemImage: "key")
        }
        .scaledFont(11).foregroundStyle(Color.inkFaint(0.55))
    }

    // MARK: Signed in

    private var signedIn: some View {
        VStack(spacing: 14) {
            Label("Connected", systemImage: "checkmark.circle.fill").scaledFont(15, .semibold).foregroundStyle(.green)
            switch account.libraryPhase {
            case .loaded:
                Text("\(account.continueWatching.count) to continue · \(account.watchHistory.count) in watch history")
                    .scaledFont(13).foregroundStyle(Color.ink.opacity(0.7))
            case .failed(let message): Text(message).scaledFont(13).foregroundStyle(.orange).multilineTextAlignment(.center)
            default: ProgressView().tint(Color.ink)
            }
            Button { Task { await account.refresh() } } label: {
                Label("Refresh", systemImage: "arrow.clockwise").scaledFont(15, .semibold).frame(maxWidth: .infinity).frame(height: 48).glassBar(Capsule())
            }.buttonStyle(PressStyle())
            Button(role: .destructive) { Task { await account.signOut(); dismiss() } } label: {
                Text("Sign out").scaledFont(15, .semibold).frame(maxWidth: .infinity).frame(height: 48).glassBar(Capsule())
            }.buttonStyle(PressStyle())
            Text("Signing out removes the session from this iPhone and ends this session only. Nuvio on your TV stays signed in.")
                .scaledFont(11).foregroundStyle(Color.inkFaint(0.5)).multilineTextAlignment(.center)
        }
    }
}
