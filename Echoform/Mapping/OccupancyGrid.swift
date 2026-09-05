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

    private func pose(_ id: String, in poses: [String: Pose]) -> Pose? {
        if let p = poses[id] { return p }
        if id.hasPrefix("Mac") { return poses["Mac"] }
        return poses["Mac"]
    }

    /// Smear each bistatic ellipsoid of revolution into the grid.
    /// Mac-L and Mac-R are 26 cm apart, so even a single built-in mic
    /// yields two intersecting families — a 3D room image without an iPhone.
    func integrate(peaks: [EchoPeak], poses: [String: Pose], c: Double) {
        var acc: [SIMD3<Int>: Float] = [:]
        let half = Int((extent / cell).rounded())
        for peak in peaks {
            guard let tx = pose(peak.transmitterID, in: poses),
                  let rx = pose(peak.receiverID, in: poses) else { continue }
            let path = Float(c * peak.delaySeconds)
            if path < 0.18 || path > extent * 2.2 { continue }
            let isDirect = poses.values.contains { p in
                p.label != tx.label && abs(simd_distance(tx.position, p.position) - path) < 0.18
            }
            if isDirect { continue }
            let baseline = simd_distance(tx.position, rx.position)
            if path <= baseline { continue }
            let major = path / 2
            let minor = sqrt(max(1e-4, major * major - (baseline / 2) * (baseline / 2)))
            let mid = (tx.position + rx.position) * 0.5
            var dir = rx.position - tx.position
            if simd_length_squared(dir) < 1e-8 {
                dir = SIMD3<Float>(1, 0, 0)
            } else {
                dir = simd_normalize(dir)
            }
            var side = simd_cross(dir, SIMD3<Float>(0, 0, 1))
            if simd_length_squared(side) < 1e-8 {
                side = simd_cross(dir, SIMD3<Float>(0, 1, 0))
            }
            side = simd_normalize(side)
            let up = simd_normalize(simd_cross(dir, side))
            let samples = 48
            let rings = 6
            for s in 0..<samples {
                let theta = Float(s) / Float(samples) * 2 * Float.pi
                let ct = cos(theta)
                let st = sin(theta)
                for r in 0..<rings {
                    let phi = Float(r) / Float(rings) * Float.pi
                    let radial = side * cos(phi) + up * sin(phi)
                    var p = mid + dir * (ct * major) + radial * (st * minor)
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
        }
        let fresh = acc.map {
            OccupancyVoxel(
                position: SIMD3(Float($0.key.x), Float($0.key.y), Float($0.key.z)) * cell,
                weight: $0.value
            )
        }
        voxels = (voxels + fresh).suffix(2800).map { $0 }
    }

    func recomputeField(poses: [Pose], wavelength: Float) {
        let w = fieldWidth
        let h = fieldHeight
        guard w > 1, h > 1 else { return }
        var f = [Float](repeating: 0, count: w * h)
        let k = 2 * Float.pi / max(wavelength, 0.002)
        let sources = poses.filter { $0.label == "Mac" || $0.label.hasPrefix("Mac-L") || $0.label.hasPrefix("Mac-R") || $0.label == "iPhone" || $0.label == "AirPods" }
        let use = sources.isEmpty ? poses : sources
        for y in 0..<h {
            for x in 0..<w {
                let px = (Float(x) / Float(w - 1) - 0.5) * extent * 2
                let py = (Float(y) / Float(h - 1) - 0.5) * extent * 1.5
                var re: Float = 0
                var im: Float = 0
                for pose in use {
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
