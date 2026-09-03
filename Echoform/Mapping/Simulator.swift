import Foundation
import simd

enum RoomSimulator {
    /// Synthetic peaks as if a 4 × 3 × 2.6 m room scattered a chirp.
    static func peaks(from poses: [Pose], c: Double) -> [EchoPeak] {
        let walls: [SIMD3<Float>] = [
            SIMD3(2.0, 0, 1.2), SIMD3(-2.0, 0, 1.2),
            SIMD3(0, 1.5, 1.2), SIMD3(0, -1.5, 1.2),
            SIMD3(0.8, 0.4, 0.9), SIMD3(-0.6, -0.7, 0.7)
        ]
        var out: [EchoPeak] = []
        for tx in poses {
            for rx in poses {
                for w in walls {
                    let path = simd_distance(tx.position, w) + simd_distance(w, rx.position)
                    let delay = Double(path) / c
                    let snr = Float(0.35 + 0.5 * exp(-Double(path)))
                    out.append(EchoPeak(delaySeconds: delay, snr: snr, transmitterID: tx.label, receiverID: rx.label))
                }
            }
        }
        return out
    }
}
