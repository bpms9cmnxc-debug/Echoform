import Foundation
import simd
import Combine

struct ScatterTrack: Identifiable, Sendable {
    var id: Int
    var position: SIMD3<Float>
    var velocity: SIMD3<Float>
    var hits: Int
    var miss: Int
    var confidence: Float
    var age: Int
}

@MainActor
final class TrackBank: ObservableObject {
    @Published var tracks: [ScatterTrack] = []
    private var nextID = 1
    var dt: Float = 0.22

    func step(detections: [OccupancyVoxel]) {
        for i in tracks.indices {
            tracks[i].position += tracks[i].velocity * dt
            tracks[i].velocity *= 0.96
            tracks[i].age += 1
            tracks[i].miss += 1
        }
        var used = Set<Int>()
        let order = tracks.indices.sorted { tracks[$0].confidence > tracks[$1].confidence }
        for ti in order {
            var bestJ: Int?
            var bestD: Float = 0.55
            for (j, d) in detections.enumerated() where !used.contains(j) {
                let dist = simd_distance(SIMD3<Float>(d.position.x, d.position.y, 0), SIMD3(tracks[ti].position.x, tracks[ti].position.y, 0))
                if dist < bestD { bestD = dist; bestJ = j }
            }
            guard let j = bestJ else { continue }
            used.insert(j)
            let det = detections[j]
            let r = det.position - tracks[ti].position
            tracks[ti].position += 0.35 * r
            tracks[ti].velocity += (0.18 / dt) * r
            tracks[ti].hits += 1
            tracks[ti].miss = 0
            tracks[ti].confidence = min(1, tracks[ti].confidence * 0.7 + 0.3 * min(1, det.weight / 8))
        }
        for (j, d) in detections.enumerated() where !used.contains(j) {
            if tracks.contains(where: { simd_distance($0.position, d.position) < 0.4 }) { continue }
            tracks.append(ScatterTrack(id: nextID, position: d.position, velocity: .zero, hits: 1, miss: 0, confidence: 0.35, age: 1))
            nextID += 1
        }
        tracks.removeAll { $0.miss >= 5 || $0.age >= 80 }
        if tracks.count > 8 { tracks = Array(tracks.prefix(8)) }
    }

    func reset() { tracks.removeAll(); nextID = 1 }
}
