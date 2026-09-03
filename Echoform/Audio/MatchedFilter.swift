import Foundation

enum MatchedFilter {
    static func correlate(record: [Float], chirp: [Float]) -> [Float] {
        let n = record.count
        let m = chirp.count
        guard n >= m + 4, m > 8 else { return [] }
        var energy: Float = 0
        for s in chirp { energy += s * s }
        let inv = energy > 1e-12 ? 1 / sqrt(energy) : 1
        var out = [Float](repeating: 0, count: n - m + 1)
        for k in 0..<out.count {
            var acc: Float = 0
            for i in 0..<m { acc += record[k + i] * chirp[i] }
            out[k] = abs(acc) * inv
        }
        return out
    }

    static func cfarPeaks(correlation: [Float], sampleRate: Double, bandID: String, maxPeaks: Int = 6, minDelay: Double = 0.0016, maxDelay: Double = 0.03) -> [EchoPeak] {
        let minIndex = max(2, Int(minDelay * sampleRate))
        let maxIndex = min(correlation.count - 2, Int(maxDelay * sampleRate))
        let guardN = 6
        let train = 20
        let pfa: Float = 3.1
        guard maxIndex > minIndex + train else { return [] }
        var candidates: [(Int, Float)] = []
        for i in minIndex..<maxIndex {
            if correlation[i] <= correlation[i - 1] || correlation[i] < correlation[i + 1] { continue }
            var noise: Float = 0
            var count: Float = 0
            let left0 = max(0, i - guardN - train)
            let left1 = max(0, i - guardN)
            let right0 = min(correlation.count, i + guardN + 1)
            let right1 = min(correlation.count, i + guardN + 1 + train)
            if left1 > left0 { for j in left0..<left1 { noise += correlation[j]; count += 1 } }
            if right1 > right0 { for j in right0..<right1 { noise += correlation[j]; count += 1 } }
            let floor = count > 0 ? noise / count : 1e-6
            let snr = correlation[i] / max(floor, 1e-8)
            if snr > pfa { candidates.append((i, snr)) }
        }
        candidates.sort { $0.1 > $1.1 }
        let minSep = max(6, Int(0.00035 * sampleRate))
        var kept: [EchoPeak] = []
        for c in candidates {
            if kept.contains(where: { abs($0.delaySeconds * sampleRate - Double(c.0)) < Double(minSep) }) { continue }
            kept.append(EchoPeak(delaySeconds: Double(c.0) / sampleRate, snr: c.1, transmitterID: "Mac", receiverID: "Mac", bandID: bandID, confidence: min(1, 0.2 + 0.05 * log2(1 + c.1))))
            if kept.count >= maxPeaks { break }
        }
        return kept
    }

    static func fuse(peaks: [EchoPeak], sampleRate: Double) -> [EchoPeak] {
        let window = 0.00035
        var used = [Bool](repeating: false, count: peaks.count)
        var fused: [EchoPeak] = []
        let order = peaks.indices.sorted { peaks[$0].snr > peaks[$1].snr }
        for i in order {
            if used[i] { continue }
            var cluster: [EchoPeak] = []
            for j in peaks.indices where !used[j] && abs(peaks[j].delaySeconds - peaks[i].delaySeconds) <= window {
                used[j] = true
                cluster.append(peaks[j])
            }
            let bands = Array(Set(cluster.map(\.bandID))).sorted()
            let wsum = cluster.reduce(Float(0)) { $0 + $1.snr }
            let delay = cluster.reduce(0.0) { $0 + $1.delaySeconds * Double($1.snr) } / Double(max(wsum, 1e-6))
            let snr = cluster.map(\.snr).max() ?? 0
            let conf = min(1, 0.28 * Float(bands.count) + 0.08 * log2(1 + snr))
            fused.append(EchoPeak(delaySeconds: delay, snr: snr, transmitterID: cluster[0].transmitterID, receiverID: cluster[0].receiverID, bandID: bands.joined(separator: "+"), confidence: conf))
        }
        return fused.sorted { $0.confidence > $1.confidence }.prefix(14).map { $0 }
    }

    static func detectHop(record: [Float], chirps: [String: [Float]], offsets: [String: Int], sampleRate: Double) -> [EchoPeak] {
        var all: [EchoPeak] = []
        for band in Band.all {
            guard let chirp = chirps[band.id], let off = offsets[band.id] else { continue }
            let slice = off < record.count ? Array(record[off...]) : []
            all.append(contentsOf: cfarPeaks(correlation: correlate(record: slice, chirp: chirp), sampleRate: sampleRate, bandID: band.id))
        }
        return fuse(peaks: all, sampleRate: sampleRate)
    }
}
