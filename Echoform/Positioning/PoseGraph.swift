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
        if #available(iOS 16.0, macOS 13.0, *) {
            uwbAvailable = true
            uwbNote = "NISession symbols present. A live session still needs a peer token from the iPhone companion — Mac UWB is best-effort."
        } else {
            uwbAvailable = false
            uwbNote = "This OS build has no Nearby Interaction surface."
        }
        #else
        uwbAvailable = false
        uwbNote = "NearbyInteraction.framework is not linked on this target. Pose graph uses manual / simulated baselines."
        #endif
    }

    func nudge(_ id: String, by delta: SIMD3<Float>) {
        guard var p = poses[id] else { return }
        p.position += delta
        poses[id] = p
    }

    var list: [Pose] { Array(poses.values) }
}
