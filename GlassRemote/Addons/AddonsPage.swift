import SwiftUI
import UIKit

/// Profile > Add-ons: the active profile's Stremio-compatible add-ons.
struct AddonsPage: View {
    @ObservedObject private var store = AddonStore.shared
    @State private var showAdd = false

    var body: some View {
        List {
            if store.addons.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No add-ons yet").font(.headline)
                        Text("Add a Stremio-compatible add-on with its install link (it usually ends in manifest.json). Stream add-ons let Play find sources for a title.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            } else {
                Section {
                    ForEach(store.addons) { addon in
                        NavigationLink {
                            AddonDetailPage(addonID: addon.id)
                        } label: {
                            AddonRow(addon: addon, name: store.displayName(for: addon), refreshing: store.refreshing.contains(addon.id))
                        }
                        .swipeActions(edge: .leading) {
                            Button(addon.enabled ? "Disable" : "Enable") { store.setEnabled(addon.id, !addon.enabled) }
                                .tint(addon.enabled ? .gray : .green)
                        }
                    }
                    .onDelete { offsets in
                        let ids = offsets.map { store.addons[$0].id }
                        ids.forEach { store.remove($0) }
                    }
                    .onMove { store.move(fromOffsets: $0, toOffset: $1) }
                } header: {
                    Text("Installed for this profile")
                } footer: {
                    Text("Play asks enabled stream add-ons in this order. Swipe right to enable or disable, left to remove. Pull to refresh.")
                }
            }
            Section {
                Button { showAdd = true } label: { Label("Add an add-on", systemImage: "plus.circle.fill") }
            }
        }
        .profileSubpage("Add-ons")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if !store.addons.isEmpty { EditButton() }
            }
        }
        .refreshable { await store.refreshAll() }
        .sheet(isPresented: $showAdd) { AddAddonSheet() }
    }
}

struct AddonLogo: View {
    let manifest: AddonManifest
    var size: CGFloat = 40
    @Environment(\.glassTheme) private var theme

    /// Only https logos are fetched; anything else shows the symbol.
    private var url: URL? {
        guard let text = manifest.logo, let url = URL(string: text), url.scheme?.lowercased() == "https" else { return nil }
        return url
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
        ZStack {
            shape.fill(theme.accent.opacity(0.16))
            if let url {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFit().padding(size * 0.08)
                    } else {
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .accessibilityHidden(true)
    }

    private var fallback: some View {
        Image(systemName: "puzzlepiece.extension.fill")
            .font(.system(size: size * 0.42))
            .foregroundStyle(theme.accent)
    }
}

struct AddonRow: View {
    let addon: InstalledAddon
    /// Shown instead of the manifest name, e.g. "Torrentio 2" when an add-on is installed twice.
    var name: String? = nil
    var refreshing = false

    var body: some View {
        HStack(spacing: 12) {
            AddonLogo(manifest: addon.manifest, size: 40)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(name ?? addon.manifest.name).font(.body.weight(.semibold)).lineLimit(1)
                    if !addon.enabled {
                        Text("Off")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Color.secondary.opacity(0.2)))
                    }
                }
                HStack(spacing: 6) {
                    ForEach(addon.manifest.capabilities) { cap in
                        Text(cap.title)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Color.secondary.opacity(0.14)))
                    }
                }
                if let error = addon.lastError {
                    Text(error).font(.caption).foregroundStyle(.orange).lineLimit(2)
                }
            }
            Spacer(minLength: 4)
            if refreshing { ProgressView() }
        }
        .opacity(addon.enabled ? 1 : 0.6)
    }
}

struct AddAddonSheet: View {
    /// Install id whose link this sheet replaces. Nil adds a new install.
    var replacing: String? = nil
    @ObservedObject private var store = AddonStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var link = ""
    @State private var installing = false
    @State private var failure: String?
    @State private var installed: InstalledAddon?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://…/manifest.json", text: $link, axis: .vertical)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .lineLimit(1...4)
                        .focused($focused)
                        .onSubmit(install)
                    Button {
                        if let text = UIPasteboard.general.string { link = text }
                    } label: {
                        Label("Paste link", systemImage: "doc.on.clipboard")
                    }
                } header: {
                    Text("Add-on link")
                } footer: {
                    Text("Use the install link from the add-on's website; stremio:// links work too. The full link is kept in the Keychain and only its address is shown.")
                }
                if let failure {
                    Section {
                        Label(failure, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                }
                if let installed {
                    Section("Installed") {
                        HStack(spacing: 12) {
                            AddonLogo(manifest: installed.manifest, size: 44)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(store.displayName(for: installed)).font(.headline)
                                Text("Version \(installed.manifest.version)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        ForEach(installed.manifest.compatibility.notes, id: \.self) { note in
                            Text(note).font(.footnote)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background { AmbientBackdrop() }
            .navigationTitle(replacing == nil ? "Add add-on" : "Replace link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(installed == nil ? "Cancel" : "Done") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if installing {
                        ProgressView()
                    } else {
                        Button("Install", action: install)
                            .disabled(link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
        .onAppear { focused = true }
        .themedSheet()
    }

    private func install() {
        guard !installing else { return }
        installing = true
        failure = nil
        let text = link
        Task {
            do {
                let addon = try await store.install(from: text, replacing: replacing)
                withAnimation(Motion.adaptive(Motion.snappy)) {
                    installed = addon
                    link = ""
                }
                Haptics.soft()
            } catch is CancellationError {
                // The profile changed while installing; nothing to report.
            } catch {
                withAnimation(Motion.adaptive(Motion.snappy)) {
                    failure = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            }
            installing = false
        }
    }
}

struct AddonDetailPage: View {
    let addonID: String
    @ObservedObject private var store = AddonStore.shared
    @EnvironmentObject private var remote: RemoteModel
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @State private var confirmRemove = false
    @State private var showReplace = false
    @State private var message: String?

    var body: some View {
        Group {
            if let addon = store.addon(addonID) {
                content(addon)
            } else {
                Text("This add-on was removed.").foregroundStyle(.secondary)
            }
        }
        .profileSubpage(store.addon(addonID).map { store.displayName(for: $0) } ?? "Add-on")
        .sheet(isPresented: $showReplace) { AddAddonSheet(replacing: addonID) }
    }

    private func content(_ addon: InstalledAddon) -> some View {
        let m = addon.manifest
        let compat = m.compatibility
        let busy = store.refreshing.contains(addonID)
        return List {
            Section {
                HStack(spacing: 14) {
                    AddonLogo(manifest: m, size: 56)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.displayName(for: addon)).font(.title3.weight(.bold))
                        Text("Version \(m.version) · \(addon.displayURL)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let text = m.description, !text.isEmpty { Text(text).font(.subheadline) }
                Toggle("Enabled", isOn: Binding(get: { store.addon(addonID)?.enabled ?? false },
                                                set: { store.setEnabled(addonID, $0) }))
            }
            if let error = addon.lastError {
                Section { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
            }
            Section("Compatibility") {
                Label(compat.usable ? "Used by Play" : "Not used by Play",
                      systemImage: compat.usable ? "checkmark.seal.fill" : "info.circle")
                    .foregroundStyle(compat.usable ? Color.green : Color.secondary)
                ForEach(compat.notes, id: \.self) { note in Text(note).font(.footnote) }
            }
            Section("Provides") {
                DeviceInfoRow("Resources", m.capabilities.isEmpty ? "None recognised" : m.capabilities.map(\.title).joined(separator: ", "))
                DeviceInfoRow("Types", m.types.isEmpty ? "Not listed" : m.types.joined(separator: ", "))
                if !m.catalogs.isEmpty {
                    DeviceInfoRow("Catalogues", m.catalogs.prefix(6).map { $0.name ?? $0.id }.joined(separator: ", "))
                }
                DeviceInfoRow("Last refreshed", addon.refreshedAt.formatted(date: .abbreviated, time: .shortened))
            }
            Section {
                if let configure = store.configureURL(for: addon) {
                    Button { openURL(configure) } label: { Label("Configure on the add-on's website", systemImage: "slider.horizontal.3") }
                }
                Button { showReplace = true } label: {
                    Label("Replace link", systemImage: "link")
                }
                Button {
                    Task { await store.refresh(addonID) }
                } label: {
                    Label(busy ? "Refreshing…" : "Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(busy)
                if let url = store.transportURL(for: addon) {
                    Button {
                        Task { message = await remote.installAddonInNuvio(manifestURL: url) }
                    } label: {
                        Label("Install in Nuvio on the TV", systemImage: "tv")
                    }
                }
                if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
            } footer: {
                Text("After reconfiguring it on its website, use Replace link to update this add-on in place. Adding a new link with Add an add-on installs a separate copy, so two configurations can be used side by side.")
            }
            Section {
                Button("Remove add-on", role: .destructive) { confirmRemove = true }
            }
        }
        .confirmationDialog("Remove \(m.name)?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                store.remove(addonID)
                dismiss()
            }
        }
    }
}
