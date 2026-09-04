import Foundation
import simd
import Combine

struct OccupancyVoxel: Sendable {
    var position: SIMD3<Float>
    var weight: Float
}

final class OccupancyGrid: ObservableObject {
    @Published var voxels: [OccupancyVoxel] = []
    @Published var field: [Float] = []
    @Published var fieldWidth = 80
    @Published var fieldHeight = 60

    var cell: Float = 0.10
    var extent: Float = 3.2

    func reset() {
        voxels.removeAll()
        field = [Float](repeating: 0, count: fieldWidth * fieldHeight)
    }

    func integrate(peaks: [EchoPeak], poses: [String: Pose], c: Double) {
        var acc: [SIMD3<Int>: Float] = [:]
        let half = Int((extent / cell).rounded())
        let mac = poses["Mac"] ?? .macOrigin
        for peak in peaks {
            guard let tx = poses[peak.transmitterID] ?? poses.values.first,
                  let rx = poses[peak.receiverID] ?? poses.values.first else { continue }
            let path = Float(c * peak.delaySeconds)
            if path < 0.18 || path > extent * 2.2 { continue }
            let isDirect = poses.values.contains { p in
                p.label != tx.label && abs(simd_distance(tx.position, p.position) - path) < 0.18
            }
            if isDirect { continue }
            let samples = 56
            let d = simd_distance(tx.position, rx.position)
            if path <= d { continue }
            let major = path / 2
            let minor = sqrt(max(1e-4, major * major - (d / 2) * (d / 2)))
            let mid = (tx.position + rx.position) * 0.5
            let dir = simd_normalize(rx.position - tx.position + SIMD3<Float>(0.001, 0, 0))
            let up = SIMD3<Float>(0, 0, 1)
            let side = simd_normalize(simd_cross(dir, up))
            for s in 0..<samples {
                let a = Float(s) / Float(samples) * 2 * Float.pi
                var p = mid + dir * (cos(a) * major) + side * (sin(a) * minor)
                p.z = max(0.15, min(2.3, p.z))
                let gi = SIMD3<Int>(
                    Int((p.x / cell).rounded()),
                    Int((p.y / cell).rounded()),
                    Int((p.z / cell).rounded())
                )
                if abs(gi.x) > half || abs(gi.y) > half || gi.z < 0 || gi.z > half { continue }
                acc[gi, default: 0] += peak.snr
            }
        }
        _ = mac
        let fresh = acc.map {
            OccupancyVoxel(
                position: SIMD3(Float($0.key.x), Float($0.key.y), Float($0.key.z)) * cell,
                weight: $0.value
            )
        }
        voxels = (voxels + fresh).suffix(1800).map { $0 }
    }

    func recomputeField(poses: [Pose], wavelength: Float) {
        let w = fieldWidth
        let h = fieldHeight
        var f = [Float](repeating: 0, count: w * h)
        let k = 2 * Float.pi / max(wavelength, 0.002)
        for y in 0..<h {
            for x in 0..<w {
                let px = (Float(x) / Float(w - 1) - 0.5) * extent * 2
                let py = (Float(y) / Float(h - 1) - 0.5) * extent * 1.5
                var re: Float = 0
                var im: Float = 0
                for pose in poses {
                    let dx = px - pose.position.x
                    let dy = py - pose.position.y
                    let r = max(0.05, sqrt(dx * dx + dy * dy))
                    let amp = 1 / r
                    let ph = k * r
                    re += amp * cos(ph)
                    im += amp * sin(ph)
                }
                f[y * w + x] = sqrt(re * re + im * im)
            }
        }
        var maxv: Float = 1e-6
        for v in f where v > maxv { maxv = v }
        for i in 0..<f.count { f[i] /= maxv }
        field = f
    }
}
