import Foundation
import simd
import Combine

struct OccupancyVoxel: Sendable {
    var position: SIMD3<Float>
    var weight: Float
}

@MainActor
final class OccupancyGrid: ObservableObject {
    @Published var voxels: [OccupancyVoxel] = []
    @Published var field: [Float] = []
    @Published var fieldWidth = 80
    @Published var fieldHeight = 60
    var cell: Float = 0.12
    var extent: Float = 3.4
    private var acc: [SIMD3<Int>: Float] = [:]

    func reset() {
        acc.removeAll(); voxels.removeAll()
        field = [Float](repeating: 0, count: fieldWidth * fieldHeight)
    }

    func integrate(peaks: [EchoPeak], poses: [String: Pose], c: Double) {
        for k in acc.keys { acc[k]! *= 0.82 }
        acc = acc.filter { $0.value >= 0.08 }
        let half = Int((extent / cell).rounded())
        for peak in peaks {
            let tx = poses[peak.transmitterID] ?? poses["Mac"] ?? poses.values.first
            let rx = poses[peak.receiverID] ?? poses["Mac"] ?? poses.values.first
            guard let tx, let rx else { continue }
            let path = Float(c * peak.delaySeconds)
            if path < 0.25 || path > extent * 2.6 { continue }
            let d = simd_distance(tx.position, rx.position)
            if path <= d + 0.04 { continue }
            let major = path / 2
            let minor = sqrt(max(1e-4, major * major - (d / 2) * (d / 2)))
            let mid = (tx.position + rx.position) * 0.5
            var dir = rx.position - tx.position
            if simd_length(dir) < 1e-4 { dir = SIMD3<Float>(1, 0, 0) }
            dir = simd_normalize(dir)
            var side = simd_cross(dir, SIMD3<Float>(0, 0, 1))
            if simd_length(side) < 1e-4 { side = SIMD3<Float>(0, 1, 0) }
            side = simd_normalize(side)
            let w = peak.confidence * peak.snr
            for s in 0..<96 {
                let a = Float(s) / 96 * 2 * Float.pi
                let p = mid + dir * (cos(a) * major) + side * (sin(a) * minor)
                let gi = SIMD3<Int>(Int((p.x / cell).rounded()), Int((p.y / cell).rounded()), Int((p.z / cell).rounded()))
                if abs(gi.x) > half || abs(gi.y) > half || abs(gi.z) > half { continue }
                acc[gi, default: 0] += w
            }
        }
        voxels = acc.map { OccupancyVoxel(position: SIMD3<Float>(Float($0.key.x), Float($0.key.y), Float($0.key.z)) * cell, weight: $0.value) }.sorted { $0.weight > $1.weight }
    }

    func localMaxima(limit: Int = 8) -> [OccupancyVoxel] {
        var peaks: [OccupancyVoxel] = []
        for v in voxels where v.weight > 0.45 {
            if peaks.contains(where: { simd_distance($0.position, v.position) < cell * 2.2 }) { continue }
            peaks.append(v)
            if peaks.count >= limit { break }
        }
        return peaks
    }

    func recomputeField(poses: [Pose], wavelengths: [Float]) {
        let w = fieldWidth, h = fieldHeight
        var f = [Float](repeating: 0, count: w * h)
        let waves = wavelengths.isEmpty ? [Float(0.018)] : wavelengths
        for y in 0..<h {
            for x in 0..<w {
                let px = (Float(x) / Float(w - 1) - 0.5) * extent * 2
                let py = (Float(y) / Float(h - 1) - 0.5) * extent * 1.5
                var mag: Float = 0
                for lambda in waves {
                    let k = 2 * Float.pi / max(lambda, 0.002)
                    var re: Float = 0, im: Float = 0
                    for pose in poses {
                        let dx = px - pose.position.x, dy = py - pose.position.y
                        let r = max(0.05, sqrt(dx * dx + dy * dy))
                        re += (1 / r) * cos(k * r); im += (1 / r) * sin(k * r)
                    }
                    mag += sqrt(re * re + im * im)
                }
                f[y * w + x] = mag
            }
        }
        let maxv = max(f.max() ?? 1e-6, 1e-6)
        for i in 0..<f.count { f[i] /= maxv }
        field = f
    }
}
