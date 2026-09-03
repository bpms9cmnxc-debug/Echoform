import Foundation
import simd
import Combine

#if canImport(NearbyInteraction)
import NearbyInteraction
#endif

@MainActor
final class PoseGraph: ObservableObject {
    @Published var poses: [String: Pose] = [
        "Mac": .macOrigin,
        "iPhone": Pose(position: SIMD3(0.7, 0.2, 0.0), covariance: 0.08, label: "iPhone"),
        "AirPods": Pose(position: SIMD3(0.12, 0.05, 0.18), covariance: 0.25, label: "AirPods")
    ]
    @Published var uwbAvailable = false
    @Published var uwbNote = "Nearby Interaction not started."

    func probeUWB() {
        #if canImport(NearbyInteraction)
        uwbAvailable = true
        uwbNote = "NISession present. Needs a peer token from the iPhone companion."
        #else
        uwbAvailable = false
        uwbNote = "NearbyInteraction not linked. Pose graph uses simulated baselines. GPS unused."
        #endif
    }

    func nudge(_ id: String, by delta: SIMD3<Float>) {
        guard var p = poses[id] else { return }
        p.position += delta
        poses[id] = p
    }

    var list: [Pose] { Array(poses.values) }
}
