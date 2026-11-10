import PhotosUI
import SwiftUI

enum ProfileEditorTarget: Identifiable, Equatable {
    case create
    case edit(UUID)

    var id: String {
        switch self {
        case .create: return "create"
        case .edit(let id): return id.uuidString
        }
    }
}

/// Create or edit a profile: any name, and an optional photo from the photo library. The system
/// photo picker runs out of process, so no photo-library permission prompt is needed.
struct ProfileEditorSheet: View {
    let target: ProfileEditorTarget
    @ObservedObject private var profiles = ProfileStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var pickedItem: PhotosPickerItem?
    /// Already downscaled JPEG of the picked photo.
    @State private var pickedData: Data?
    @State private var preview: UIImage?
    @State private var removePhoto = false
    @State private var loadingPhoto = false
    @State private var saving = false
    @State private var confirmDelete = false
    @State private var message: String?

    private var editing: UserProfile? {
        if case .edit(let id) = target { return profiles.profiles.first { $0.id == id } }
        return nil
    }

    private var hasPhoto: Bool { preview != nil || (!removePhoto && editing?.hasImage == true) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 14) {
                        avatar
                        PhotosPicker(selection: $pickedItem, matching: .images, photoLibrary: .shared()) {
                            Label(hasPhoto ? "Change photo" : "Choose photo", systemImage: "photo.on.rectangle")
                        }
                        if hasPhoto {
                            Button("Remove photo", role: .destructive) {
                                pickedItem = nil
                                pickedData = nil
                                preview = nil
                                removePhoto = true
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .listRowBackground(Color.clear)
                }
                Section("Name") {
                    TextField("Profile name", text: $name)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .onSubmit(save)
                        .onChange(of: name) { value in
                            if value.count > UserProfile.maxNameLength { name = String(value.prefix(UserProfile.maxNameLength)) }
                        }
                }
                if let message {
                    Section { Text(message).foregroundStyle(.red) }
                }
                if editing != nil && profiles.profiles.count > 1 {
                    Section {
                        Button("Delete profile", role: .destructive) { confirmDelete = true }
                    } footer: {
                        Text("Removes this profile's photo, add-ons and settings. TV pairings are shared by all profiles and stay.")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background { AmbientBackdrop() }
            .navigationTitle(editing == nil ? "New profile" : "Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editing == nil ? "Create" : "Save", action: save)
                        .disabled(UserProfile.cleanedName(name) == nil || saving || loadingPhoto)
                }
            }
            .confirmationDialog("Delete \(editing?.name ?? "profile")?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete profile", role: .destructive) {
                    if let id = editing?.id {
                        withAnimation(Motion.resolve(Motion.theme, reduceMotion: false)) { profiles.delete(id) }
                    }
                    dismiss()
                }
            }
        }
        .onAppear { if let editing, name.isEmpty { name = editing.name } }
        .onChange(of: pickedItem) { item in loadPhoto(item) }
        .themedSheet()
    }

    private var avatar: some View {
        let stored = removePhoto ? nil : editing.flatMap { profiles.image(for: $0.id) }
        return AvatarCircle(image: preview ?? stored,
                            initials: UserProfile(name: name.isEmpty ? "?" : name).initials,
                            tint: editing?.tint ?? 0, size: 104)
            .overlay { if loadingPhoto { ProgressView().tint(.white) } }
            .animation(Motion.snappy, value: preview != nil)
    }

    private func loadPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        loadingPhoto = true
        message = nil
        Task {
            let raw = try? await item.loadTransferable(type: Data.self)
            let jpeg = await Task.detached(priority: .userInitiated) { raw.flatMap { ProfileImageProcessing.avatarJPEG(from: $0) } }.value
            loadingPhoto = false
            guard let jpeg, let image = UIImage(data: jpeg) else {
                message = "That photo couldn't be loaded. Try another one."
                return
            }
            pickedData = jpeg
            preview = image
            removePhoto = false
        }
    }

    private func save() {
        guard !saving, let clean = UserProfile.cleanedName(name) else { return }
        saving = true
        let id: UUID
        if let editing {
            profiles.rename(editing.id, to: clean)
            id = editing.id
        } else {
            guard let created = profiles.create(name: clean) else {
                message = "You can have up to \(ProfileStore.maxProfiles) profiles."
                saving = false
                return
            }
            id = created.id
        }
        let data = pickedData
        let remove = removePhoto
        let isNew = editing == nil
        Task {
            if let data {
                let stored = await profiles.setImage(data, for: id)
                if !stored { message = "The photo couldn't be saved." }
            } else if remove {
                await profiles.setImage(nil, for: id)
            }
            if isNew { withAnimation(Motion.resolve(Motion.theme, reduceMotion: false)) { profiles.switchTo(id) } }
            saving = false
            dismiss()
        }
    }
}
