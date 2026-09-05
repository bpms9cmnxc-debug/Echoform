import Foundation
import simd

enum RoomSimulator {
    /// Static scatterers that a stationary MacBook can still image:
    /// four walls, floor/ceiling samples, furniture. No iPhone required.
    static let walls: [SIMD3<Float>] = [
        SIMD3( 2.4,  0.0, 1.20),
        SIMD3( 2.4,  0.9, 0.45),
        SIMD3( 2.4, -0.9, 1.80),
        SIMD3(-2.4,  0.0, 1.20),
        SIMD3(-2.4,  0.8, 0.50),
        SIMD3(-2.4, -0.7, 1.70),
        SIMD3( 0.0,  1.8, 1.20),
        SIMD3( 0.9,  1.8, 0.55),
        SIMD3(-0.9,  1.8, 1.75),
        SIMD3( 0.0, -1.8, 1.20),
        SIMD3( 1.0, -1.8, 0.40),
        SIMD3(-0.8, -1.8, 1.85),
        SIMD3( 1.4, -0.9, 0.72),
        SIMD3(-1.1,  0.8, 0.90),
        SIMD3( 0.6,  0.4, 0.48),
        SIMD3(-0.4, -0.6, 0.78),
        SIMD3( 1.8,  1.1, 2.15),
        SIMD3(-1.6, -1.0, 2.15),
        SIMD3( 0.2,  0.1, 2.20),
        SIMD3( 2.0, -1.4, 1.10),
        SIMD3(-2.0,  1.3, 0.95),
    ]

    static func isTransmitter(_ p: Pose, all: [Pose], airpodsTX: Bool) -> Bool {
        if p.label == "AirPods" { return airpodsTX }
        if p.label.hasPrefix("Mac-Mic") { return false }
        if p.label == "Mac" {
            return !all.contains { $0.label == "Mac-L" || $0.label == "Mac-R" }
        }
        return true
    }

    static func isReceiver(_ p: Pose, all: [Pose]) -> Bool {
        if p.label == "AirPods" { return false }
        if p.label.hasPrefix("Mac-L") || p.label.hasPrefix("Mac-R") { return false }
        if p.label == "Mac" {
            return !all.contains { $0.label.hasPrefix("Mac-Mic") }
        }
        return true
    }

    /// Direct path (device ranging) plus wall scatter. AirPods is TX only.
    /// Mac-L / Mac-R fire independently; each Mac-Mic is its own RX.
    static func peaks(from poses: [Pose], c: Double, airpodsTX: Bool = true) -> [EchoPeak] {
        let txList = poses.filter { isTransmitter($0, all: poses, airpodsTX: airpodsTX) }
        let rxList = poses.filter { isReceiver($0, all: poses) }
        var out: [EchoPeak] = []
        for tx in txList {
            for rx in rxList {
                let d = simd_distance(tx.position, rx.position)
                if d > 0.04 {
                    let extra = tx.label == "AirPods" ? 0.0016 : 0.0
                    out.append(EchoPeak(
                        delaySeconds: Double(d) / c + extra,
                        snr: Float(1.6 / (0.4 + d)),
                        transmitterID: tx.label,
                        receiverID: rx.label
                    ))
                }
                for w in walls {
                    let path = simd_distance(tx.position, w) + simd_distance(w, rx.position)
                    let delay = Double(path) / c
                    let snr = Float(0.35 + 0.60 * exp(-Double(path) * 0.35))
                    out.append(EchoPeak(delaySeconds: delay, snr: snr, transmitterID: tx.label, receiverID: rx.label))
                }
            }
        }
        return out
    }

    static func movingScatterers(t: Double) -> [SIMD3<Float>] {
        let tt = Float(t)
        let walker = SIMD3(0.15 + 1.45 * sin(tt * 0.72), 0.20 + 1.05 * cos(tt * 0.51), 1.4)
        let door = SIMD3(1.85 + 0.45 * cos(tt * 0.58), 0.85 + 0.7 * sin(tt * 0.58), 1.1)
        return walls + [walker, door]
    }
}
