import SwiftUI
import UIKit

/// Gradients for initials avatars (profiles without a photo).
enum AvatarPalette {
    static let gradients: [[Color]] = [
        [Color(red: 0.36, green: 0.52, blue: 1.0), Color(red: 0.56, green: 0.33, blue: 0.96)],
        [Color(red: 1.0, green: 0.55, blue: 0.33), Color(red: 0.93, green: 0.27, blue: 0.47)],
        [Color(red: 0.2, green: 0.78, blue: 0.64), Color(red: 0.12, green: 0.5, blue: 0.86)],
        [Color(red: 0.98, green: 0.76, blue: 0.24), Color(red: 0.95, green: 0.45, blue: 0.2)],
        [Color(red: 0.74, green: 0.4, blue: 0.98), Color(red: 0.98, green: 0.4, blue: 0.7)],
        [Color(red: 0.45, green: 0.52, blue: 0.62), Color(red: 0.2, green: 0.25, blue: 0.34)],
    ]

    static func colors(_ tint: Int) -> [Color] {
        let n = gradients.count
        return gradients[((tint % n) + n) % n]
    }
}

struct AvatarCircle: View {
    let image: UIImage?
    let initials: String
    let tint: Int
    let size: CGFloat

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                LinearGradient(colors: AvatarPalette.colors(tint), startPoint: .topLeading, endPoint: .bottomTrailing)
                Text(initials)
                    .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.5)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
        .accessibilityHidden(true)
    }
}

/// A profile's photo or initials, optionally with an accent ring (the active profile).
struct ProfileAvatar: View {
    let profile: UserProfile
    var size: CGFloat = 44
    var ring = false
    @ObservedObject private var store = ProfileStore.shared
    @Environment(\.glassTheme) private var theme

    var body: some View {
        AvatarCircle(image: store.image(for: profile.id), initials: profile.initials, tint: profile.tint, size: size)
            .padding(ring ? max(3, size * 0.045) : 0)
            .overlay {
                if ring { Circle().strokeBorder(theme.accent, lineWidth: max(2, size * 0.03)) }
            }
    }
}
