import SwiftUI

/// Create, edit, reorder and delete Quick Actions. Everything is stored on this iPhone.
struct QuickActionEditor: View {
    @ObservedObject var store: QuickActionStore
    @Environment(\.dismiss) private var dismiss
    @State private var path: [UUID] = []

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach($store.actions) { $action in
                    NavigationLink(value: action.id) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(action.name).font(.body.weight(.semibold))
                            Text(action.summary { RemoteModel.shared.appName(forPackage: $0) })
                                .font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                }
                .onDelete { store.actions.remove(atOffsets: $0) }
                .onMove { store.actions.move(fromOffsets: $0, toOffset: $1) }

                Button {
                    let created = store.add()
                    path.append(created.id)
                } label: {
                    Label("New Quick Action", systemImage: "plus")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .navigationTitle("Quick Actions")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: UUID.self) { id in
                if let index = store.actions.firstIndex(where: { $0.id == id }) {
                    ActionDetail(action: $store.actions[index])
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { EditButton() }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.large])
        .preferredColorScheme(.dark)
    }
}

private struct ActionDetail: View {
    @Binding var action: QuickAction
    private let apps = RemoteModel.shared.apps

    var body: some View {
        List {
            Section("Name") {
                TextField("Name", text: $action.name)
            }

            Section("Steps") {
                ForEach($action.steps) { $step in
                    StepRow(step: $step, apps: apps)
                }
                .onDelete { action.steps.remove(atOffsets: $0) }
                .onMove { action.steps.move(fromOffsets: $0, toOffset: $1) }

                Menu {
                    Button { action.steps.append(.launch(apps.first?.package ?? "")) } label: { Label("Open app", systemImage: "square.grid.2x2") }
                    Button { action.steps.append(.key("HOME")) } label: { Label("Press key", systemImage: "circle.grid.cross") }
                    Button { action.steps.append(.delay(1)) } label: { Label("Wait", systemImage: "clock") }
                    Button { action.steps.append(.volume("VOLUME_UP", count: 1)) } label: { Label("Volume steps", systemImage: "speaker.wave.2") }
                } label: {
                    Label("Add step", systemImage: "plus")
                }
            }

            Section {
                Text("Steps run in order. Waits are capped at 30 seconds and volume steps at 20 presses.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.black)
        .navigationTitle(action.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .navigationBarTrailing) { EditButton() } }
    }
}

private struct StepRow: View {
    @Binding var step: QuickActionStep
    let apps: [TVApp]

    var body: some View {
        switch step.kind {
        case .launch:
            Picker("Open app", selection: $step.package) {
                ForEach(apps) { app in Text(app.name).tag(app.package) }
            }
        case .key:
            Picker("Press key", selection: $step.key) {
                ForEach(QuickActionStore.allowedKeys, id: \.self) { key in
                    Text(QuickActionStore.keyTitles[key] ?? key).tag(key)
                }
            }
        case .delay:
            Stepper(value: $step.seconds, in: 0.5...30, step: 0.5) {
                Text("Wait \(String(format: "%g", step.seconds)) s")
            }
        case .volume:
            VStack(alignment: .leading, spacing: 8) {
                Picker("Direction", selection: $step.key) {
                    Text("Volume up").tag("VOLUME_UP")
                    Text("Volume down").tag("VOLUME_DOWN")
                }
                .pickerStyle(.segmented)
                Stepper(value: $step.count, in: 1...20) { Text("\(step.count) press\(step.count == 1 ? "" : "es")") }
            }
        }
    }
}
