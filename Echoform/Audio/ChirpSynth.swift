import Foundation

struct ChirpSpec: Equatable {
    var sampleRate: Double = 48_000
    var startHz: Double = 18_000
    var stopHz: Double = 19_500
    var duration: Double = 0.008
    var amplitude: Float = 0.12
    var sampleCount: Int { Int((duration * sampleRate).rounded()) }
}

enum ChirpSynth {
    static func samples(_ spec: ChirpSpec) -> [Float] {
        let n = max(spec.sampleCount, 16)
        let amp = min(max(spec.amplitude, 0), SafetyLimits.maxPeakAmplitude)
        let T = Double(n) / spec.sampleRate
        let f0 = spec.startHz
        let k = (spec.stopHz - spec.startHz) / T
        var out = [Float](repeating: 0, count: n)
        let taper = max(8, n / 16)
        for i in 0..<n {
            let t = Double(i) / spec.sampleRate
            let phase = 2 * Double.pi * (f0 * t + 0.5 * k * t * t)
            var w: Float = 1
            if i < taper { w = Float(0.5 - 0.5 * cos(Double.pi * Double(i) / Double(taper))) }
            else if i > n - taper { w = Float(0.5 - 0.5 * cos(Double.pi * Double(n - i) / Double(taper))) }
            out[i] = amp * w * Float(sin(phase))
        }
        return out
    }

    static func hopTrain(sampleRate: Double, amplitude: Float = 0.12) -> (samples: [Float], offsets: [String: Int], chirps: [String: [Float]]) {
        var offsets: [String: Int] = [:]
        var chirps: [String: [Float]] = [:]
        var n = 0
        let amp = amplitude / Float(Band.all.count)
        for band in Band.all {
            let c = Self.samples(ChirpSpec(sampleRate: sampleRate, startHz: band.startHz, stopHz: band.stopHz, amplitude: amp))
            chirps[band.id] = c
            offsets[band.id] = 0
            n = max(n, c.count)
        }
        var samples = [Float](repeating: 0, count: n)
        for band in Band.all {
            guard let c = chirps[band.id] else { continue }
            for i in 0..<c.count { samples[i] += c[i] }
        }
        return (samples, offsets, chirps)
    }
}
