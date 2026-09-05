import Foundation
import Accelerate

enum MatchedFilter {
    /// FFT-based correlation of `record` against `chirp`. Returns |R| aligned
    /// so index 0 is zero delay. Both buffers are real.
    static func correlate(record: [Float], chirp: [Float]) -> [Float] {
        let n = 1 << Int(ceil(log2(Double(max(16, record.count + chirp.count)))))
        var a = [Float](repeating: 0, count: n)
        var b = [Float](repeating: 0, count: n)
        for i in 0..<min(record.count, n) { a[i] = record[i] }
        for i in 0..<min(chirp.count, n) { b[i] = chirp[i] }

        // Don't use log2(Double(n)) — 2^k can round to k-1 and scramble the FFT.
        let log2n = vDSP_Length(Int(log2(Double(n)).rounded()))
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            return []
        }
        defer { vDSP_destroy_fftsetup(setup) }

        var realA = [Float](repeating: 0, count: n/2)
        var imagA = [Float](repeating: 0, count: n/2)
        var realB = [Float](repeating: 0, count: n/2)
        var imagB = [Float](repeating: 0, count: n/2)

        a.withUnsafeMutableBufferPointer { ap in
            b.withUnsafeMutableBufferPointer { bp in
                ap.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n/2) { ac in
                    bp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n/2) { bc in
                        var splitA = DSPSplitComplex(realp: &realA, imagp: &imagA)
                        var splitB = DSPSplitComplex(realp: &realB, imagp: &imagB)
                        vDSP_ctoz(ac, 2, &splitA, 1, vDSP_Length(n/2))
                        vDSP_ctoz(bc, 2, &splitB, 1, vDSP_Length(n/2))
                        vDSP_fft_zrip(setup, &splitA, 1, log2n, FFTDirection(kFFTDirection_Forward))
                        vDSP_fft_zrip(setup, &splitB, 1, log2n, FFTDirection(kFFTDirection_Forward))
                        // multiply A * conj(B)
                        var tmpR = [Float](repeating: 0, count: n/2)
                        var tmpI = [Float](repeating: 0, count: n/2)
                        // Packed real FFT: imagp[0] is Nyquist (real), not an imaginary part.
                        tmpR[0] = realA[0] * realB[0]
                        tmpI[0] = imagA[0] * imagB[0]
                        for i in 1..<(n/2) {
                            tmpR[i] = realA[i] * realB[i] + imagA[i] * imagB[i]
                            tmpI[i] = imagA[i] * realB[i] - realA[i] * imagB[i]
                        }
                        tmpR.withUnsafeMutableBufferPointer { tr in
                            tmpI.withUnsafeMutableBufferPointer { ti in
                                var splitC = DSPSplitComplex(realp: tr.baseAddress!, imagp: ti.baseAddress!)
                                vDSP_fft_zrip(setup, &splitC, 1, log2n, FFTDirection(kFFTDirection_Inverse))
                                var packed = [Float](repeating: 0, count: n)
                                packed.withUnsafeMutableBufferPointer { pp in
                                    pp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n/2) { pc in
                                        vDSP_ztoc(&splitC, 1, pc, 2, vDSP_Length(n/2))
                                    }
                                }
                                var mag = [Float](repeating: 0, count: n)
                                var scale: Float = 1.0 / Float(n)
                                vDSP_vsmul(packed, 1, &scale, &packed, 1, vDSP_Length(n))
                                for i in 0..<n { mag[i] = abs(packed[i]) }
                                realA = mag
                            }
                        }
                    }
                }
            }
        }
        return realA
    }

    static func pickPeaks(correlation: [Float], sampleRate: Double, maxPeaks: Int = 8, minDelay: Double = 0.0004) -> [(delay: Double, snr: Float)] {
        guard let maxv = correlation.max(), maxv > 1e-6 else { return [] }
        let minIndex = Int(minDelay * sampleRate)
        // Negative lags wrap to the end of the FFT. Treat those as walls
        // and you get 0.7 s "peaks" that drown the real echoes.
        let maxIndex = min(correlation.count - 1, max(minIndex + 1, Int(0.04 * sampleRate)))
        var candidates: [(Int, Float)] = []
        if correlation.count < 3 { return [] }
        for i in max(1, minIndex)..<maxIndex {
            if correlation[i] > correlation[i - 1], correlation[i] >= correlation[i + 1], correlation[i] > 0.12 * maxv {
                candidates.append((i, correlation[i] / maxv))
            }
        }
        candidates.sort { $0.1 > $1.1 }
        return candidates.prefix(maxPeaks).map { (Double($0.0) / sampleRate, $0.1) }
    }
}
