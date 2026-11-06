import SwiftUI
import UIKit

struct ScreenshotItem: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// Shows a screenshot of the TV with share / save. Nothing is stored unless the person shares it.
struct ScreenshotSheet: View {
    let item: ScreenshotItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Image(uiImage: item.image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding()
                    .accessibilityLabel("Screenshot of the TV")
                Text("Protected video (Netflix, Prime…) appears black in screenshots.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.bottom)
            }
            .background { AmbientBackdrop() }
            .navigationTitle("TV screenshot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    ShareLink(
                        item: Image(uiImage: item.image),
                        preview: SharePreview("TV screenshot", image: Image(uiImage: item.image))
                    )
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .themedSheet()
    }
}
