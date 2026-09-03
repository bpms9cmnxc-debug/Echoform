import Foundation
import simd

enum Atmosphere {
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
    var bandID: String
    var confidence: Float
}

struct SafetyLimits {
    static let maxPeakAmplitude: Float = 0.18
    static let maxChirpSeconds: Double = 0.012
    static let maxDutyCycle: Double = 0.08
    static let warnFrequencyHz: Double = 19_000
}

struct Band: Equatable, Sendable {
    var id: String
    var startHz: Double
    var stopHz: Double
    var label: String
    static let all: [Band] = [
        Band(id: "L", startHz: 8_500, stopHz: 10_500, label: "8.5–10.5 kHz"),
        Band(id: "A", startHz: 16_500, stopHz: 18_000, label: "16.5–18 kHz"),
        Band(id: "B", startHz: 18_000, stopHz: 19_500, label: "18–19.5 kHz"),
        Band(id: "C", startHz: 19_500, stopHz: 21_000, label: "19.5–21 kHz"),
    ]
}
