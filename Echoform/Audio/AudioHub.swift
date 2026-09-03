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

    let spec: ChirpSpec
    private let engine = AVAudioEngine()
    private var player = AVAudioPlayerNode()
    private var chirp: [Float] = []
    private var recording: [Float] = []
    private var tapInstalled = false

    init(spec: ChirpSpec = ChirpSpec()) {
        self.spec = spec
        self.chirp = ChirpSynth.samples(spec)
        refreshDevices()
    }

    func refreshDevices() {
        // System default plus whatever Core Audio exposes through AVAudioEngine.
        var list: [AudioDeviceInfo] = [
            AudioDeviceInfo(id: "system-default", name: "System default (Mac / AirPods if selected in Settings)", hasInput: true, hasOutput: true)
        ]
        #if os(macOS)
        list.append(AudioDeviceInfo(id: "builtin", name: "Mac built-in", hasInput: true, hasOutput: true))
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
        let sessionOK = true
        _ = sessionOK
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        if !tapInstalled {
            input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
                guard let self else { return }
                let frames = Int(buffer.frameLength)
                guard let ch = buffer.floatChannelData?[0] else { return }
                var chunk = [Float](repeating: 0, count: frames)
                for i in 0..<frames { chunk[i] = ch[i] }
                Task { @MainActor in
                    self.recording.append(contentsOf: chunk)
                    if self.recording.count > Int(self.spec.sampleRate * 0.6) {
                        self.recording.removeFirst(self.recording.count - Int(self.spec.sampleRate * 0.4))
                    }
                    var rms: Float = 0
                    vDSP_rmsqv(chunk, 1, &rms, vDSP_Length(chunk.count))
                    self.inputLevel = rms
                }
            }
            tapInstalled = true
        }
        if engine.attachedNodes.contains(player) == false {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
        }
        try engine.start()
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

    func ping() {
        Task { await emitAndPick() }
    }

    private func emitAndPick() async {
        do {
            if !(await requestPermission()) { return }
            try arm()
        } catch {
            lastError = error.localizedDescription
            return
        }
        recording.removeAll(keepingCapacity: true)
        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        let rate = format.sampleRate > 0 ? format.sampleRate : spec.sampleRate
        var specNow = spec
        specNow.sampleRate = rate
        let samples = ChirpSynth.samples(specNow)
        guard let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else { return }
        pcm.frameLength = AVAudioFrameCount(samples.count)
        if let dest = pcm.floatChannelData {
            let chans = Int(format.channelCount)
            for c in 0..<chans {
                for i in 0..<samples.count { dest[c][i] = samples[i] }
            }
        }
        player.stop()
        player.play()
        player.scheduleBuffer(pcm, completionHandler: nil)

        try? await Task.sleep(nanoseconds: 180_000_000)

        let corr = MatchedFilter.correlate(record: recording, chirp: samples)
        let peaks = MatchedFilter.pickPeaks(correlation: corr, sampleRate: rate)
        lastPeaks = peaks.map {
            EchoPeak(delaySeconds: $0.delay, snr: $0.snr, transmitterID: selectedOutputID ?? "out", receiverID: selectedInputID ?? "in")
        }
    }
}

import Accelerate
