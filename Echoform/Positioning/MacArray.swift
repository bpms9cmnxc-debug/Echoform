import Foundation
import simd

/// Approximate acoustic layout of a 14"/16" MacBook Pro.
///
/// Core Audio exposes the six-speaker system as stereo (L/R) and the
/// three-mic array as 1–3 input channels. Offsets are metres relative to
/// the keyboard-centre origin already used as `Pose.macOrigin`.
///
/// +X right, +Y toward the hinge, +Z up. Speakers sit on the left/right
/// edges; mics along the deck. Even with one beamformed mic channel the
/// L/R speaker baseline (~26 cm) is enough for two intersecting bistatic
/// ellipsoids — that is the Mac-only 3D image, no iPhone required.
enum MacArray {
    struct Element: Sendable, Equatable {
        var id: String
        var offset: SIMD3<Float>
        var outputChannel: Int?
        var inputChannel: Int?
        var kind: Kind
        enum Kind { case speaker, mic }
    }

    /// Left / right speaker clusters. Force-cancelling woofers + tweeters
    /// on 14"/16" Pro collapse to these two independently driven channels.
    static let speakers: [Element] = [
        Element(id: "Mac-L", offset: SIMD3(-0.132, 0.012, -0.008), outputChannel: 0, inputChannel: nil, kind: .speaker),
        Element(id: "Mac-R", offset: SIMD3( 0.132, 0.012, -0.008), outputChannel: 1, inputChannel: nil, kind: .speaker),
    ]

    /// Three-mic array. If HAL only offers one channel we keep the centre mic.
    static let mics: [Element] = [
        Element(id: "Mac-MicL", offset: SIMD3(-0.068, 0.048, 0.006), outputChannel: nil, inputChannel: 0, kind: .mic),
        Element(id: "Mac-MicC", offset: SIMD3( 0.000, 0.055, 0.006), outputChannel: nil, inputChannel: 1, kind: .mic),
        Element(id: "Mac-MicR", offset: SIMD3( 0.068, 0.048, 0.006), outputChannel: nil, inputChannel: 2, kind: .mic),
    ]

    static func speakerID(channel: Int, outputCount: Int) -> String {
        if outputCount <= 1 { return "Mac-L" }
        return channel == 0 ? "Mac-L" : "Mac-R"
    }

    static func micID(channel: Int, inputCount: Int) -> String {
        if inputCount <= 1 { return "Mac-MicC" }
        if inputCount == 2 { return channel == 0 ? "Mac-MicL" : "Mac-MicR" }
        switch channel {
        case 0: return "Mac-MicL"
        case 1: return "Mac-MicC"
        default: return "Mac-MicR"
        }
    }

    static func poses(origin: Pose, inputChannels: Int, outputChannels: Int) -> [String: Pose] {
        var dict: [String: Pose] = [origin.label: origin]
        let nOut = max(1, outputChannels)
        for s in speakers {
            guard let ch = s.outputChannel, ch < nOut || nOut == 1 && ch == 0 else { continue }
            if nOut == 1 && ch != 0 { continue }
            dict[s.id] = Pose(position: origin.position + s.offset, covariance: 0.012, label: s.id)
        }
        let nIn = max(1, inputChannels)
        if nIn == 1 {
            let m = mics[1] // centre
            dict[m.id] = Pose(position: origin.position + m.offset, covariance: 0.014, label: m.id)
        } else if nIn == 2 {
            for m in [mics[0], mics[2]] {
                dict[m.id] = Pose(position: origin.position + m.offset, covariance: 0.014, label: m.id)
            }
        } else {
            for m in mics.prefix(min(3, nIn)) {
                dict[m.id] = Pose(position: origin.position + m.offset, covariance: 0.014, label: m.id)
            }
        }
        return dict
    }

    static var simulationPoses: [String: Pose] {
        poses(origin: .macOrigin, inputChannels: 3, outputChannels: 2)
    }
}
