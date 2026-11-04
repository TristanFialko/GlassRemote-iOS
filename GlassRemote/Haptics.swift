import UIKit

/// Shared, pre-warmed haptic generators. Creating a generator per tap adds latency and the
/// first tap after idle can be missed; these are created once and re-primed after each use.
@MainActor
enum Haptics {
    private static let softGen = UIImpactFeedbackGenerator(style: .soft)
    private static let lightGen = UIImpactFeedbackGenerator(style: .light)
    private static let mediumGen = UIImpactFeedbackGenerator(style: .medium)

    static func soft() { softGen.impactOccurred(); softGen.prepare() }
    static func light() { lightGen.impactOccurred(); lightGen.prepare() }
    static func medium() { mediumGen.impactOccurred(); mediumGen.prepare() }
    static func prepare() { softGen.prepare(); lightGen.prepare(); mediumGen.prepare() }
}
