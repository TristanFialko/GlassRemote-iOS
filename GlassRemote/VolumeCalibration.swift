import Foundation

/// Maps the slider (0...1) to the TV's raw volume and back.
///
/// The TV's own scale is 0...100 on paper, but a TV can settle slightly inside it (a user saw the
/// slider stop near 2 % and 98 %). `lo`/`hi` are the raw values that mean 0 % and 100 %. They
/// start at 0 and 100 and are only narrowed when the TV demonstrably refuses to go further
/// (see `EndpointLearner`). Pure and unit tested.
struct VolumeCalibration: Equatable {
    var lo = 0
    var hi = 100

    static let standard = VolumeCalibration()

    private static let key = "glassRemote.volumeCalibration.v1"
    static func loaded(_ defaults: UserDefaults = .standard) -> VolumeCalibration {
        guard let pair = defaults.array(forKey: key) as? [Int], pair.count == 2,
              pair[0] >= 0, pair[1] <= 200, pair[1] - pair[0] >= 20 else { return .standard }
        return VolumeCalibration(lo: pair[0], hi: pair[1])
    }
    func save(_ defaults: UserDefaults = .standard) { defaults.set([lo, hi], forKey: Self.key) }

    private var span: Int { max(hi - lo, 1) }

    func raw(forFraction fraction: Double) -> Int {
        let f = min(max(fraction, 0), 1)
        if f <= 0 { return lo }
        if f >= 1 { return hi }
        return lo + Int((f * Double(span)).rounded())
    }

    func fraction(forRaw raw: Int) -> Double {
        min(max(Double(raw - lo) / Double(span), 0), 1)
    }

    /// Snap a dragged value within `margin` of an end to that end exactly, so a finger that
    /// stops a hair short still reaches 0 % or 100 %.
    static func magnet(_ value: Double, margin: Double = 0.012) -> Double {
        if value <= margin { return 0 }
        if value >= 1 - margin { return 1 }
        return value
    }
}

/// Learns where the TV really stops, conservatively. A limit is only established when ALL hold:
///  - the user commanded an end (0 % or 100 %) and nothing newer has happened since (no other
///    volume command, no drag, no volume key);
///  - readings arrive after the TV had `settleDelay` to act (so a reading that was already in
///    flight when the command was sent cannot count) and before `window` expires;
///  - the SAME value is read `requiredReadings` times at least `minSpacing` apart (settled, not moving);
///  - that value is within `tolerance` of the command and plausible (>= 80 for a top, <= 20 for a floor).
/// Any reading that breaks a rule discards the attempt. A limit found once is only TENTATIVE
/// (used this session, never saved); a second independent attempt landing on the same value makes
/// it CONFIRMED (saved). A later reading outside the learned range resets to 0...100.
struct EndpointLearner {
    struct Config {
        var settleDelay: TimeInterval = 1.0
        var window: TimeInterval = 10.0
        var minSpacing: TimeInterval = 0.7
        var requiredReadings = 3
        var tolerance = 6
    }

    enum Outcome: Equatable {
        case none
        case tentative(VolumeCalibration)
        case confirmed(VolumeCalibration)
    }

    var config = Config()
    private var command: (raw: Int, isMax: Bool, at: Date)?
    private var stableValue: Int?
    private var stableCount = 0
    private var lastStableAt = Date.distantPast
    private var tentativeMax: Int?
    private var tentativeMin: Int?

    var isArmed: Bool { command != nil }

    mutating func commandSent(raw: Int, isMax: Bool, at: Date = Date()) {
        command = (raw, isMax, at)
        stableValue = nil; stableCount = 0; lastStableAt = .distantPast
    }

    /// A newer command, a drag, or any other disturbance.
    mutating func invalidate() {
        command = nil
        stableValue = nil; stableCount = 0; lastStableAt = .distantPast
    }

    /// Forget tentative results too (calibration was reset).
    mutating func resetAll() {
        invalidate()
        tentativeMax = nil; tentativeMin = nil
    }

    mutating func reading(_ raw: Int, at: Date = Date(), dragging: Bool,
                          calibration: VolumeCalibration) -> Outcome {
        if dragging { invalidate(); return .none }
        guard let command else { return .none }
        let age = at.timeIntervalSince(command.at)
        if age > config.window { invalidate(); return .none }            // stale attempt
        if age < config.settleDelay { return .none }                      // TV has not settled yet
        if raw == command.raw { invalidate(); return .none }              // TV honoured the command
        guard abs(raw - command.raw) <= config.tolerance,
              command.isMax ? raw >= 80 : raw <= 20 else { invalidate(); return .none }   // inconsistent

        if raw == stableValue {
            guard at.timeIntervalSince(lastStableAt) >= config.minSpacing else { return .none }
            stableCount += 1
        } else {
            stableValue = raw; stableCount = 1
        }
        lastStableAt = at
        guard stableCount >= config.requiredReadings else { return .none }

        var updated = calibration
        if command.isMax { updated.hi = raw } else { updated.lo = raw }
        let isMax = command.isMax
        invalidate()
        guard updated.hi - updated.lo >= 20 else { return .none }
        let previous = isMax ? tentativeMax : tentativeMin
        if isMax { tentativeMax = raw } else { tentativeMin = raw }
        return previous == raw ? .confirmed(updated) : .tentative(updated)
    }
}
