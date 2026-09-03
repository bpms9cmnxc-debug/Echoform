import Foundation
import simd

enum Atmosphere {
    /// Speed of sound, m/s. Default 20 °C.
    static func speedOfSound(celsius: Double = 20) -> Double {
        331.3 + 0.606 * celsius
    }
}

struct Pose: Sendable, Equatable {
    var position: SIMD3<Float>
    var covariance: Float
    var label: String

    static let macOrigin = Pose(position: .zero, covariance: 0.02, label: "Mac")
}

struct EchoPeak: Sendable {
    var delaySeconds: Double
    var snr: Float
    var transmitterID: String
    var receiverID: String
}

struct SafetyLimits {
    static let maxPeakAmplitude: Float = 0.18
    static let maxChirpSeconds: Double = 0.012
    static let maxDutyCycle: Double = 0.08
    static let warnFrequencyHz: Double = 19_000
}
