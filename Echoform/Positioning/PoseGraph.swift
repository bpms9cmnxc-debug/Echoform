import Foundation
import simd
import Combine

@MainActor
final class PoseGraph: ObservableObject {
    /// Ground-truth for the acoustic simulator only.
    var truth: [String: Pose] = [
        "Mac": .macOrigin,
        "iPhone": Pose(position: SIMD3(1.15, 0.35, 1.08), covariance: 0.08, label: "iPhone"),
        "AirPods": Pose(position: SIMD3(0.22, 0.12, 1.58), covariance: 0.22, label: "AirPods"),
    ]
    /// ToF-filtered estimates shown in the 3D view.
    @Published var poses: [String: Pose] = [
        "Mac": .macOrigin,
        "iPhone": Pose(position: SIMD3(1.15, 0.35, 1.08), covariance: 0.08, label: "iPhone"),
        "AirPods": Pose(position: SIMD3(0.22, 0.12, 1.58), covariance: 0.22, label: "AirPods"),
    ]
    @Published var trails: [String: [SIMD3<Float>]] = [
        "iPhone": [],
        "AirPods": [],
    ]
    @Published var uwbAvailable = false
    @Published var uwbNote = "Auto-Track aus Chirp-Laufzeit. UWB ohne Developer-ID aus."

    private var t: Double = 0
    private var velocity: [String: SIMD3<Float>] = [:]

    var list: [Pose] { Array(poses.values) }
    var truthList: [Pose] { Array(truth.values) }

    func probeUWB() {
        uwbAvailable = false
        uwbNote = "UWB aus. Positionen kommen aus ToF-Auto-Track."
    }

    func reset() {
        t = 0
        truth = [
            "Mac": .macOrigin,
            "iPhone": Pose(position: SIMD3(1.15, 0.35, 1.08), covariance: 0.08, label: "iPhone"),
            "AirPods": Pose(position: SIMD3(0.22, 0.12, 1.58), covariance: 0.22, label: "AirPods"),
        ]
        poses = truth
        trails = ["iPhone": [], "AirPods": []]
        velocity = [:]
    }

    func stepTruth(dt: Double) {
        t += dt
        let tt = Float(t)
        if var phone = truth["iPhone"] {
            phone.position = SIMD3(1.25 * cos(tt * 0.55), 0.95 * sin(tt * 0.41), 1.05 + 0.08 * sin(tt * 1.1))
            truth["iPhone"] = phone
        }
        let wx = 0.15 + 1.45 * sin(tt * 0.72)
        let wy = 0.20 + 1.05 * cos(tt * 0.51)
        if var buds = truth["AirPods"] {
            buds.position = SIMD3(wx + 0.06, wy + 0.05, 1.58 + 0.04 * sin(tt * 2.2))
            truth["AirPods"] = buds
        }
    }

    func nudge(_ id: String, by delta: SIMD3<Float>) {
        guard var p = poses[id] else { return }
        p.position += delta
        poses[id] = p
    }

    /// Snap each node onto its measured Mac range circle, keep height, smooth velocity.
    func track(peaks: [EchoPeak], c: Double, dt: Double) {
        guard let mac = poses["Mac"] else { return }
        let step = Float(max(0.08, min(0.9, dt)))
        for id in ["iPhone", "AirPods"] {
            guard var est = poses[id] else { continue }
            let hits = peaks.filter {
                ($0.transmitterID == id && $0.receiverID == "Mac") ||
                ($0.transmitterID == "Mac" && $0.receiverID == id)
            }
            let pred = est.position + (velocity[id] ?? .zero) * step
            let predR = simd_distance(SIMD3(pred.x, pred.y, 0), SIMD3(mac.position.x, mac.position.y, 0))
            var measR = predR
            if let best = hits.min(by: { abs($0.delaySeconds - Double(predR) / c) < abs($1.delaySeconds - Double(predR) / c) }) {
                let r = Float(c * best.delaySeconds)
                if r > 0.12 && r < 3.6 { measR = r }
            }
            let dx = pred.x - mac.position.x
            let dy = pred.y - mac.position.y
            let n = max(1e-4, sqrt(dx * dx + dy * dy))
            let snap = SIMD3(mac.position.x + dx / n * measR, mac.position.y + dy / n * measR, est.position.z)
            let a: Float = 0.42
            let nx = pred.x + a * (snap.x - pred.x)
            let ny = pred.y + a * (snap.y - pred.y)
            let nz = id == "AirPods" ? Float(1.58) : Float(1.08)
            let nv = SIMD3((nx - est.position.x) / step, (ny - est.position.y) / step, 0) * 0.82
            velocity[id] = nv
            est.position = SIMD3(nx, ny, nz)
            est.covariance = 0.05 + abs(measR - predR) * 0.4
            poses[id] = est
            var trail = trails[id] ?? []
            trail.append(est.position)
            if trail.count > 48 { trail.removeFirst(trail.count - 48) }
            trails[id] = trail
        }
        poses["Mac"] = .macOrigin
    }

    func speed(of id: String) -> Float {
        let v = velocity[id] ?? .zero
        return simd_length(v)
    }

    func range(of id: String) -> Float {
        guard let p = poses[id], let mac = poses["Mac"] else { return 0 }
        return simd_distance(SIMD3(p.position.x, p.position.y, 0), SIMD3(mac.position.x, mac.position.y, 0))
    }
}
