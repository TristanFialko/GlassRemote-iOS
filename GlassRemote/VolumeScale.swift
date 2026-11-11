import Foundation

// Phase 9 continuation §C2: an honest 0–100 % volume.
//
// The slider used to show the 1…20 step index as if it were a level, and never said 100. Every
// target now has its own raw range, normalised to a real percentage for display and converted back
// to that target's raw scale for commands. Pure and unit tested (Phase9VolumeTests).
//
// Ranges (inspected per target, not shared):
// - Samsung over UPnP RenderingControl: the TV reports and accepts an absolute 0…100, narrowed only
//   by a learned calibration (VolumeCalibration / EndpointLearner). A floor above 0 is a minimum, not
//   mute.
// - Samsung over its remote socket only (no readable level): one KEY_VOLUP / KEY_VOLDOWN per step of
//   the soundbar's own scale (`tvVolumeMax`, 5…200, set in Connection settings).
// - Android over ADB: VOLUME_UP / VOLUME_DOWN key events on the music stream. Its real range comes
//   from `cmd media_session volume --stream 3 --get` ("volume is 7 in range [0..15]") when the box
//   answers; until then the original 20-step assumption stands.

/// One target's real volume range.
struct VolumeScale: Equatable, Sendable {
    enum Route: Equatable, Sendable {
        case samsungAbsolute
        case samsungKeys
        case androidKeys
    }

    var route: Route
    /// Raw value that means 0 %.
    var lo: Int
    /// Raw value that means 100 %.
    var hi: Int

    /// The Android fallback when the box has not reported its range.
    static let defaultAndroidLevels = 20

    static func samsungAbsolute(_ calibration: VolumeCalibration) -> VolumeScale {
        VolumeScale(route: .samsungAbsolute, lo: calibration.lo, hi: max(calibration.hi, calibration.lo + 1))
    }

    static func samsungKeys(max levels: Int) -> VolumeScale {
        VolumeScale(route: .samsungKeys, lo: 0, hi: Swift.max(levels, 1))
    }

    static func android(_ reported: AndroidVolumeReading?) -> VolumeScale {
        guard let reported, reported.max > reported.min else {
            return VolumeScale(route: .androidKeys, lo: 0, hi: defaultAndroidLevels)
        }
        return VolumeScale(route: .androidKeys, lo: reported.min, hi: reported.max)
    }

    /// Raw steps between 0 % and 100 %.
    var steps: Int { max(hi - lo, 1) }

    /// 0 % is silence only when the floor is raw 0. A calibrated floor above 0 is a minimum level.
    var floorIsMute: Bool { lo <= 0 }

    /// The raw value a slider fraction asks for. Only the very ends map to the ends: any non-zero
    /// fraction is at least one step above the floor, anything short of full is below the top.
    func raw(forFraction fraction: Double) -> Int {
        let f = fraction.isFinite ? min(max(fraction, 0), 1) : 0
        if f <= 0 { return lo }
        if f >= 1 { return hi }
        guard steps >= 2 else { return f < 0.5 ? lo : hi }
        let step = Int((f * Double(steps)).rounded())
        return lo + min(max(step, 1), steps - 1)
    }

    func fraction(forRaw raw: Int) -> Double {
        min(max(Double(raw - lo) / Double(steps), 0), 1)
    }

    /// 0 only at the floor, 100 only at the top; everything between is 1…99.
    func percent(forRaw raw: Int) -> Int {
        if raw <= lo { return 0 }
        if raw >= hi { return 100 }
        let p = Int((Double(raw - lo) / Double(steps) * 100).rounded())
        return min(max(p, 1), 99)
    }

    /// What the slider shows: the percentage of the raw level the fraction really commands.
    func percent(forFraction fraction: Double) -> Int { percent(forRaw: raw(forFraction: fraction)) }

    func fraction(forPercent percent: Int) -> Double { Double(min(max(percent, 0), 100)) / 100 }

    /// The real level a fraction lands on, counted from the floor (drives the per-step haptic).
    func step(forFraction fraction: Double) -> Int { raw(forFraction: fraction) - lo }

    /// VoiceOver increment: one real step on short scales, about 5 % on long ones.
    var accessibilityStep: Int { max(1, Int((Double(steps) * 0.05).rounded())) }

    /// The fraction one accessibility increment away from `fraction`, on a real level.
    func adjusted(_ fraction: Double, up: Bool) -> Double {
        let current = self.raw(forFraction: fraction)
        let next = up ? min(current + accessibilityStep, hi) : max(current - accessibilityStep, lo)
        return self.fraction(forRaw: next)
    }
}

/// The Android box's own report of its music-stream volume.
struct AndroidVolumeReading: Equatable, Sendable {
    var current: Int
    var min: Int
    var max: Int

    /// The shell commands that report it, tried in order (Android 10+, then the older `media` tool).
    static let commands: [[String]] = [
        ["cmd", "media_session", "volume", "--stream", "3", "--get"],
        ["media", "volume", "--stream", "3", "--get"]
    ]

    /// Parses "volume is 7 in range [0..15]" (with or without the "[v]" prefix of older builds).
    static func parse(_ output: String) -> AndroidVolumeReading? {
        guard let range = output.range(of: #"volume is (\d+) in range \[(\d+)\.\.(\d+)\]"#, options: .regularExpression) else {
            return nil
        }
        let numbers = output[range].split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard numbers.count == 3, numbers[2] > numbers[1], numbers[2] - numbers[1] <= 1000 else { return nil }
        let current = Swift.min(Swift.max(numbers[0], numbers[1]), numbers[2])
        return AndroidVolumeReading(current: current, min: numbers[1], max: numbers[2])
    }
}

/// One device reading, numbered so the slider settles on it even when the value repeats.
struct VolumeReadingEvent: Equatable, Sendable {
    var fraction: Double
    var serial: Int
}

/// Who owns the slider right now (pure): TV readings never fight a finger, and after a drag the
/// device's settled value is read back once and shown.
struct VolumeSync: Equatable {
    /// The TV can lag behind a command; a reading inside this window after the last user change may
    /// be stale (it was already in flight), so it is not allowed to pull the thumb back.
    var holdoff: TimeInterval = 2.0
    private(set) var dragging = false
    private(set) var lastUserChange = Date.distantPast
    private(set) var reconcilePending = false

    mutating func dragBegan(at now: Date = Date()) {
        dragging = true
        lastUserChange = now
        reconcilePending = false
    }

    /// Any user change (drag step or VoiceOver increment) restarts the hold-off and asks for a
    /// read-back once it has passed.
    mutating func userChanged(at now: Date = Date()) {
        lastUserChange = now
        reconcilePending = true
    }

    mutating func dragEnded(at now: Date = Date()) {
        dragging = false
        lastUserChange = now
        reconcilePending = true
    }

    func acceptsReading(at now: Date = Date()) -> Bool {
        !dragging && now.timeIntervalSince(lastUserChange) >= holdoff
    }

    /// A device reading: the fraction to show now, or nil while the user owns the slider (or when
    /// it would not move the thumb).
    mutating func reading(_ fraction: Double, showing current: Double, at now: Date = Date()) -> Double? {
        guard acceptsReading(at: now) else { return nil }
        reconcilePending = false
        return abs(fraction - current) > 0.0001 ? fraction : nil
    }

    /// True once, when the hold-off after a drag has passed: read the device again so the slider
    /// settles on what the TV really did.
    mutating func reconcileDue(at now: Date = Date()) -> Bool {
        guard reconcilePending, acceptsReading(at: now) else { return false }
        reconcilePending = false
        return true
    }
}

/// When the slider taps the finger (pure): once per real level the user moves through. Readings
/// from the TV, programmatic updates and repeated callbacks for the same level never tick.
enum VolumeHapticPolicy {
    static func shouldTick(previousStep: Int?, newStep: Int, userInitiated: Bool) -> Bool {
        guard userInitiated, let previousStep else { return false }
        return previousStep != newStep
    }
}

/// The slider's text, glyph and VoiceOver value (pure).
enum VolumeReadout {
    static func text(percent: Int) -> String { "\(min(max(percent, 0), 100))%" }

    static func symbol(percent: Int, floorIsMute: Bool) -> String {
        switch percent {
        case ...0: return floorIsMute ? "speaker.slash.fill" : "speaker.fill"
        case 1...33: return "speaker.wave.1.fill"
        case 34...66: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }

    static func accessibilityValue(percent: Int, floorIsMute: Bool) -> String {
        if percent <= 0 { return floorIsMute ? "Muted, 0 percent" : "Minimum, 0 percent" }
        return "\(min(percent, 100)) percent"
    }
}
