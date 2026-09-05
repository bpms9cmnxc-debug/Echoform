import Foundation
import AVFoundation
import Combine
import Accelerate

struct AudioDeviceInfo: Identifiable, Hashable {
    var id: String
    var name: String
    var hasInput: Bool
    var hasOutput: Bool
}

@MainActor
final class AudioHub: ObservableObject {
    @Published var devices: [AudioDeviceInfo] = []
    @Published var selectedInputID: String?
    @Published var selectedOutputID: String?
    @Published var lastPeaks: [EchoPeak] = []
    @Published var isArmed = false
    @Published var lastError: String?
    @Published var inputLevel: Float = 0
    @Published var inputChannelCount = 1
    @Published var outputChannelCount = 2

    let spec: ChirpSpec
    private let engine = AVAudioEngine()
    private var player = AVAudioPlayerNode()
    private var chirp: [Float] = []
    private var recordingCh: [[Float]] = [[]]
    private var tapInstalled = false

    init(spec: ChirpSpec = ChirpSpec()) {
        self.spec = spec
        self.chirp = ChirpSynth.samples(spec)
        refreshDevices()
    }

    /// Pose-graph keys are "Mac" / "iPhone" / "AirPods". Device picker IDs are not.
    func poseID(forDeviceID id: String?) -> String {
        switch id {
        case "airpods": return "AirPods"
        default: return "Mac"
        }
    }

    var usesMacArray: Bool {
        selectedOutputID != "airpods" && selectedInputID != "airpods"
    }

    func refreshDevices() {
        var list: [AudioDeviceInfo] = [
            AudioDeviceInfo(id: "system-default", name: "System default (Mac array / AirPods if selected in Settings)", hasInput: true, hasOutput: true)
        ]
        #if os(macOS)
        list.append(AudioDeviceInfo(id: "builtin", name: "Mac built-in (L/R speakers + mic array)", hasInput: true, hasOutput: true))
        list.append(AudioDeviceInfo(id: "airpods", name: "AirPods (if connected as system I/O)", hasInput: true, hasOutput: true))
        list.append(AudioDeviceInfo(id: "usb", name: "USB interface (if present)", hasInput: true, hasOutput: true))
        #endif
        devices = list
        if selectedInputID == nil { selectedInputID = list.first?.id }
        if selectedOutputID == nil { selectedOutputID = list.first?.id }
    }

    func requestPermission() async -> Bool {
        #if os(macOS)
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            lastError = "Microphone permission denied."
            return false
        }
        #else
        return true
        #endif
    }

    func arm() throws {
        if isArmed { return }
        if engine.attachedNodes.contains(player) == false {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: nil)
        }
        engine.prepare()
        try engine.start()
        // Format is 0 Hz until the engine is running. Installing the tap first
        // froze a dead layout and the chirp never matched the recording.
        if !tapInstalled {
            let input = engine.inputNode
            let fmt = input.inputFormat(forBus: 0)
            let nch = max(1, Int(fmt.channelCount))
            inputChannelCount = nch
            recordingCh = Array(repeating: [], count: nch)
            input.installTap(onBus: 0, bufferSize: 4096, format: fmt.sampleRate > 0 ? fmt : nil) { [weak self] buffer, _ in
                guard let self else { return }
                let frames = Int(buffer.frameLength)
                guard frames > 0, let src = buffer.floatChannelData else { return }
                let chans = Int(buffer.format.channelCount)
                var chunks = Array(repeating: [Float](), count: max(1, chans))
                for c in 0..<max(1, chans) {
                    var chunk = [Float](repeating: 0, count: frames)
                    let ptr = src[c]
                    for i in 0..<frames { chunk[i] = ptr[i] }
                    chunks[c] = chunk
                }
                var rms: Float = 0
                vDSP_rmsqv(chunks[0], 1, &rms, vDSP_Length(chunks[0].count))
                Task { @MainActor in
                    if self.recordingCh.count != chunks.count {
                        self.recordingCh = Array(repeating: [], count: chunks.count)
                        self.inputChannelCount = chunks.count
                    }
                    for c in 0..<chunks.count {
                        self.recordingCh[c].append(contentsOf: chunks[c])
                        let cap = Int(self.spec.sampleRate * 0.6)
                        if self.recordingCh[c].count > cap {
                            self.recordingCh[c].removeFirst(self.recordingCh[c].count - Int(self.spec.sampleRate * 0.4))
                        }
                    }
                    self.inputLevel = rms
                }
            }
            tapInstalled = true
        }
        let outFmt = engine.mainMixerNode.outputFormat(forBus: 0)
        outputChannelCount = max(1, Int(outFmt.channelCount))
        isArmed = true
        lastError = nil
    }

    func disarm() {
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        player.stop()
        engine.stop()
        isArmed = false
    }

    func ping() async {
        await emitAndPick()
    }

    private func emitAndPick() async {
        do {
            if !(await requestPermission()) { return }
            try arm()
        } catch {
            lastError = error.localizedDescription
            return
        }
        for i in 0..<recordingCh.count { recordingCh[i].removeAll(keepingCapacity: true) }
        let format = player.outputFormat(forBus: 0)
        let playFormat = format.sampleRate > 0 && format.channelCount > 0
            ? format
            : engine.mainMixerNode.outputFormat(forBus: 0)
        guard playFormat.sampleRate > 0, playFormat.channelCount > 0 else {
            lastError = "Audio format not ready."
            return
        }
        let rate = playFormat.sampleRate
        let outCh = Int(playFormat.channelCount)
        outputChannelCount = max(1, outCh)

        var specL = spec
        specL.sampleRate = rate
        specL.startHz = 18_000
        specL.stopHz = 19_500
        var specR = spec
        specR.sampleRate = rate
        specR.startHz = 19_500
        specR.stopHz = 21_000
        let chirpL = ChirpSynth.samples(specL)
        let chirpR = ChirpSynth.samples(specR)
        let n = max(chirpL.count, chirpR.count)
        guard let pcm = AVAudioPCMBuffer(pcmFormat: playFormat, frameCapacity: AVAudioFrameCount(n)) else { return }
        pcm.frameLength = AVAudioFrameCount(n)
        if let dest = pcm.floatChannelData {
            for c in 0..<outCh {
                let src = (c == 0 || outCh == 1) ? chirpL : chirpR
                for i in 0..<n {
                    dest[c][i] = i < src.count ? src[i] : 0
                }
            }
        }
        player.stop()
        player.play()
        player.scheduleBuffer(pcm, completionHandler: nil)

        try? await Task.sleep(nanoseconds: 240_000_000)

        let array = usesMacArray
        var peaks: [EchoPeak] = []
        let recs = recordingCh
        inputChannelCount = max(1, recs.count)
        for (ci, rec) in recs.enumerated() {
            let rx: String
            if array {
                rx = MacArray.micID(channel: ci, inputCount: recs.count)
            } else {
                rx = poseID(forDeviceID: selectedInputID)
            }
            let corrL = MatchedFilter.correlate(record: rec, chirp: chirpL)
            let pickL = MatchedFilter.pickPeaks(correlation: corrL, sampleRate: rate)
            let txL = array ? MacArray.speakerID(channel: 0, outputCount: outCh) : poseID(forDeviceID: selectedOutputID)
            peaks.append(contentsOf: pickL.map {
                EchoPeak(delaySeconds: $0.delay, snr: $0.snr, transmitterID: txL, receiverID: rx)
            })
            if outCh > 1 && array {
                let corrR = MatchedFilter.correlate(record: rec, chirp: chirpR)
                let pickR = MatchedFilter.pickPeaks(correlation: corrR, sampleRate: rate)
                let txR = MacArray.speakerID(channel: 1, outputCount: outCh)
                peaks.append(contentsOf: pickR.map {
                    EchoPeak(delaySeconds: $0.delay, snr: $0.snr, transmitterID: txR, receiverID: rx)
                })
            }
        }
        lastPeaks = peaks
    }
}
