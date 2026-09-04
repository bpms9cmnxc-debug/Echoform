import Foundation
import simd

enum RoomSimulator {
    static let walls: [SIMD3<Float>] = [
        SIMD3( 2.4,  0.0, 1.25),
        SIMD3(-2.4,  0.0, 1.25),
        SIMD3( 0.0,  1.8, 1.25),
        SIMD3( 0.0, -1.8, 1.25),
        SIMD3( 1.4, -0.9, 0.72),
        SIMD3(-1.1,  0.8, 0.90),
    ]

    /// Direct path (device ranging) plus wall scatter. AirPods is TX only.
    static func peaks(from poses: [Pose], c: Double, airpodsTX: Bool = true) -> [EchoPeak] {
        let txList = poses.filter { $0.label != "AirPods" || airpodsTX }
        let rxList = poses.filter { $0.label != "AirPods" }
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
                    let snr = Float(0.4 + 0.55 * exp(-Double(path)))
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
