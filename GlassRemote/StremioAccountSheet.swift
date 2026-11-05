import SwiftUI

/// Connect / disconnect the Stremio account. Stremio offers no OAuth or web sign-in flow for third
/// parties; its own apps send email + password to api.strem.io and keep the returned session key.
/// This sheet does exactly that and no more: the password is held in this view's memory only until
/// the request returns, then cleared; only the session key is stored (Keychain).
struct StremioAccountSheet: View {
    @ObservedObject private var account = StremioAccount.shared
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @FocusState private var focus: Field?
    private enum Field { case email, password }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: "person.crop.circle").scaledFont(46, .light).foregroundStyle(.white.opacity(0.7)).padding(.top, 28)
                Text("Stremio account").scaledFont(22, .bold)
                switch account.state {
                case .signedIn: signedIn
                case .signingIn: ProgressView().tint(.white).padding()
                case .signedOut, .expired: signedOut
                }
            }
            .padding(.horizontal, 24).padding(.bottom, 24)
        }
        .foregroundStyle(.white)
        .background { AmbientBackdrop() }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }

    private var signedOut: some View {
        VStack(spacing: 14) {
            if account.state == .expired {
                Label("Your session expired. Sign in again.", systemImage: "exclamationmark.triangle").scaledFont(13, .semibold).foregroundStyle(.orange)
            }
            Text("Shows your Continue Watching and Library from Stremio. Read-only: this app never changes your library.")
                .scaledFont(13).foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.center)
            VStack(spacing: 10) {
                TextField("Email", text: $email)
                    .textContentType(.username).keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($focus, equals: .email).submitLabel(.next).onSubmit { focus = .password }
                    .padding(.horizontal, 16).frame(height: 48).glassBar(Capsule())
                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .focused($focus, equals: .password).submitLabel(.go).onSubmit { submit() }
                    .padding(.horizontal, 16).frame(height: 48).glassBar(Capsule())
            }
            if let error = account.signInError { Text(error).scaledFont(13).foregroundStyle(.orange).multilineTextAlignment(.center) }
            Button(action: submit) {
                Text("Connect").scaledFont(16, .semibold).frame(maxWidth: .infinity).frame(height: 52).glassBar(Capsule())
            }
            .buttonStyle(PressStyle())
            .disabled(email.isEmpty || password.isEmpty).opacity(email.isEmpty || password.isEmpty ? 0.5 : 1)
            VStack(alignment: .leading, spacing: 6) {
                Label("Stremio has no web or OAuth sign-in for apps, so your password is sent over HTTPS to api.strem.io (Stremio's own server) and nowhere else.", systemImage: "lock.shield")
                Label("The password is never saved or logged. Only Stremio's session key is kept, in the iOS Keychain on this iPhone.", systemImage: "key")
                Label("Accounts created only with Facebook or Apple have no Stremio password; set one at stremio.com first.", systemImage: "info.circle")
            }
            .scaledFont(11).foregroundStyle(.white.opacity(0.55))
        }
    }

    private var signedIn: some View {
        VStack(spacing: 14) {
            Label("Connected", systemImage: "checkmark.circle.fill").scaledFont(15, .semibold).foregroundStyle(.green)
            switch account.libraryPhase {
            case .loaded:
                Text("\(account.library.count) in library · \(account.continueWatching.count) to continue")
                    .scaledFont(13).foregroundStyle(.white.opacity(0.7))
            case .failed(let message): Text(message).scaledFont(13).foregroundStyle(.orange).multilineTextAlignment(.center)
            default: ProgressView().tint(.white)
            }
            Button { Task { await account.refresh() } } label: {
                Label("Refresh", systemImage: "arrow.clockwise").scaledFont(15, .semibold).frame(maxWidth: .infinity).frame(height: 48).glassBar(Capsule())
            }.buttonStyle(PressStyle())
            Button(role: .destructive) { Task { await account.signOut(); dismiss() } } label: {
                Text("Sign out").scaledFont(15, .semibold).frame(maxWidth: .infinity).frame(height: 48).glassBar(Capsule())
            }.buttonStyle(PressStyle())
            Text("Signing out removes the session key from this iPhone and ends it on Stremio's server.")
                .scaledFont(11).foregroundStyle(.white.opacity(0.5)).multilineTextAlignment(.center)
        }
    }

    private func submit() {
        guard !email.isEmpty, !password.isEmpty else { return }
        let mail = email, pass = password
        password = ""          // cleared from the field immediately; the request keeps its own copy
        focus = nil
        Task {
            await account.signIn(email: mail, password: pass)
            if account.state == .signedIn { email = "" }
        }
    }
}
