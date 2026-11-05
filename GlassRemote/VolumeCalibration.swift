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

    /// Fraction of the slider, measured from either end, inside which a drag snaps to that end.
    /// Both ends use this one value, so the snap zone is exactly symmetric.
    static let magnetMargin = 0.015

    /// Snap a dragged value within `margin` of an end to that end exactly, so a finger that
    /// stops a hair short still reaches 0 % or 100 %. The distance to each end is measured the
    /// same way (`value` from 0, `1 - value` from 1) and compared with a tiny epsilon, so a
    /// value sitting exactly on the boundary (e.g. 0.985) is not lost to binary rounding of
    /// `1 - margin`. Values outside 0...1 are clamped first.
    static func magnet(_ value: Double, margin: Double = magnetMargin) -> Double {
        let v = min(max(value, 0), 1)
        let epsilon = 1e-9
        if v <= margin + epsilon { return 0 }
        if 1 - v <= margin + epsilon { return 1 }
        return v
    }
}

/// Learns where the TV really stops. After the user commands an end of the range and the TV then
/// reports the SAME value twice in a row (and that value differs from the command by at most
/// `tolerance`), that value is the real end. Nothing is learned from a single reading, from a
/// reading that is still moving, or from a value far from the command.
struct EndpointLearner {
    var tolerance = 6
    private var commanded: (raw: Int, isMax: Bool)?
    private var last: Int?
    private var repeats = 0

    mutating func commandSent(raw: Int, isMax: Bool) {
        commanded = (raw, isMax)
        last = nil
        repeats = 0
    }

    mutating func clear() { commanded = nil; last = nil; repeats = 0 }

    /// Returns an updated calibration when a limit was learned.
    mutating func reading(_ raw: Int, calibration: VolumeCalibration) -> VolumeCalibration? {
        guard let commanded else { return nil }
        if raw == commanded.raw { clear(); return nil }               // TV honoured the command
        guard abs(raw - commanded.raw) <= tolerance else { clear(); return nil }
        if raw == last { repeats += 1 } else { last = raw; repeats = 1 }
        guard repeats >= 2 else { return nil }
        var updated = calibration
        if commanded.isMax { updated.hi = raw } else { updated.lo = raw }
        clear()
        return updated.hi - updated.lo >= 20 ? updated : nil
    }
}
