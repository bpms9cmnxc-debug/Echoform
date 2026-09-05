import Foundation
import simd
import Combine

@MainActor
final class PoseGraph: ObservableObject {
    /// Ground-truth for the acoustic simulator only.
    var truth: [String: Pose] = MacArray.simulationPoses
    /// ToF-filtered estimates shown in the 3D view.
    @Published var poses: [String: Pose] = MacArray.simulationPoses
    @Published var trails: [String: [SIMD3<Float>]] = [:]
    @Published var uwbAvailable = false
    @Published var uwbNote = "Mac-Array: Stereo-Lautsprecher + alle Mikrofone. iPhone optional."
    /// When false the 3D image is produced from the MacBook’s own speakers and mics.
    @Published var useCompanions = false

    private var t: Double = 0
    private var velocity: [String: SIMD3<Float>] = [:]
    private var lastInputChannels = 3
    private var lastOutputChannels = 2

    var list: [Pose] { Array(poses.values) }
    var truthList: [Pose] { Array(truth.values) }

    func probeUWB() {
        uwbAvailable = false
        uwbNote = useCompanions
            ? "UWB aus. Positionen kommen aus ToF-Auto-Track."
            : "Nur Mac. L/R-Chirps und alle Mic-Kanäle bauen die 3D-Wolke."
    }

    func setArrayChannels(input: Int, output: Int) {
        lastInputChannels = max(1, input)
        lastOutputChannels = max(1, output)
        rebuildArray()
    }

    func setUseCompanions(_ on: Bool) {
        useCompanions = on
        rebuildArray()
        probeUWB()
    }

    private func rebuildArray() {
        let origin = Pose.macOrigin
        var next = MacArray.poses(origin: origin, inputChannels: lastInputChannels, outputChannels: lastOutputChannels)
        var nextTruth = MacArray.poses(origin: origin, inputChannels: max(lastInputChannels, 3), outputChannels: max(lastOutputChannels, 2))
        if useCompanions {
            let phone = Pose(position: SIMD3(1.15, 0.35, 1.08), covariance: 0.08, label: "iPhone")
            let buds = Pose(position: SIMD3(0.22, 0.12, 1.58), covariance: 0.22, label: "AirPods")
            next["iPhone"] = poses["iPhone"] ?? phone
            next["AirPods"] = poses["AirPods"] ?? buds
            nextTruth["iPhone"] = truth["iPhone"] ?? phone
            nextTruth["AirPods"] = truth["AirPods"] ?? buds
            if trails["iPhone"] == nil { trails["iPhone"] = [] }
            if trails["AirPods"] == nil { trails["AirPods"] = [] }
        } else {
            next.removeValue(forKey: "iPhone")
            next.removeValue(forKey: "AirPods")
            nextTruth.removeValue(forKey: "iPhone")
            nextTruth.removeValue(forKey: "AirPods")
            trails["iPhone"] = nil
            trails["AirPods"] = nil
        }
        poses = next
        truth = nextTruth
    }

    func reset() {
        t = 0
        velocity = [:]
        trails = useCompanions ? ["iPhone": [], "AirPods": []] : [:]
        rebuildArray()
    }

    func stepTruth(dt: Double) {
        guard useCompanions else { return }
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

    /// Snap each companion onto its measured Mac range circle. Mac-array
    /// elements stay bolted to the chassis — they are the instrument.
    func track(peaks: [EchoPeak], c: Double, dt: Double) {
        guard useCompanions, let mac = poses["Mac"] else {
            poses["Mac"] = .macOrigin
            return
        }
        let step = Float(max(0.08, min(0.9, dt)))
        for id in ["iPhone", "AirPods"] {
            guard var est = poses[id] else { continue }
            let hits = peaks.filter {
                ($0.transmitterID == id && ($0.receiverID == "Mac" || $0.receiverID.hasPrefix("Mac-Mic"))) ||
                (($0.transmitterID == "Mac" || $0.transmitterID.hasPrefix("Mac-")) && $0.receiverID == id)
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

    var arraySummary: String {
        let tx = poses.keys.filter { $0.hasPrefix("Mac-L") || $0.hasPrefix("Mac-R") }.count
        let rx = poses.keys.filter { $0.hasPrefix("Mac-Mic") }.count
        return "Mac-Array  \(max(tx, 1)) TX  ·  \(max(rx, 1)) RX"
    }
}
