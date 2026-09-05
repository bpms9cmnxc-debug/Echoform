import SwiftUI
import simd
import Combine

struct ContentView: View {
    @StateObject private var audio = AudioHub()
    @StateObject private var poses = PoseGraph()
    @StateObject private var grid = OccupancyGrid()
    @State private var simulate = true
    @State private var auto = true
    @State private var temperature = 20.0
    @State private var status = "Mac-Array an. iPhone nicht nötig."
    @State private var hops = 0
    @State private var last = Date()

    private let tick = Timer.publish(every: 0.38, on: .main, in: .common).autoconnect()

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 14) {
                header
                controls
                deviceList
                peaks
                Spacer()
                footer
            }
            .padding(16)
            .frame(minWidth: 340, idealWidth: 380)

            VStack(spacing: 8) {
                CloudView(voxels: grid.voxels, poses: poses.list, trails: poses.trails)
                    .frame(minWidth: 520, minHeight: 420)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1)
                FieldView(field: grid.field, width: grid.fieldWidth, height: grid.fieldHeight)
                    .frame(height: 140)
                    .overlay(alignment: .topLeading) {
                        Text("Interferenz  ·  konstruktiv / destruktiv")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(8)
                    }
            }
            .padding(12)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            poses.probeUWB()
            fire()
        }
        .onReceive(tick) { _ in
            if auto { fire() }
        }
        .onChange(of: audio.inputChannelCount) { _, n in
            poses.setArrayChannels(input: n, output: audio.outputChannelCount)
        }
        .onChange(of: audio.outputChannelCount) { _, n in
            poses.setArrayChannels(input: audio.inputChannelCount, output: n)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ECHOFORM")
                .font(.system(size: 22, weight: .semibold, design: .monospaced))
            Text("Mac-Array 3D  ·  ohne iPhone  ·  Stereo-Chirp L/R")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Simulation", isOn: $simulate)
            Toggle("Auto-Track", isOn: $auto)
            Toggle("iPhone & AirPods", isOn: Binding(
                get: { poses.useCompanions },
                set: { poses.setUseCompanions($0); fire() }
            ))
            HStack {
                Button("Arm I/O") {
                    Task {
                        do {
                            try audio.arm()
                            poses.setArrayChannels(input: audio.inputChannelCount, output: audio.outputChannelCount)
                            status = "Engine running · \(audio.outputChannelCount) out · \(audio.inputChannelCount) in."
                        } catch {
                            status = error.localizedDescription
                        }
                    }
                }
                Button("Ping") { fire() }
                    .keyboardShortcut(.space, modifiers: [])
                Button("Clear") {
                    grid.reset()
                    poses.reset()
                    hops = 0
                    status = "Grid und Tracks geleert."
                    refreshField()
                }
            }
            .buttonStyle(.borderedProminent)
            Slider(value: $temperature, in: 10...30, step: 0.5) {
                Text("Luft \(temperature, specifier: "%.1f") °C")
            }
            Text(status)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(poses.uwbNote)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var deviceList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Nodes").font(.headline)
            ForEach(nodeIDs, id: \.self) { id in
                if let p = poses.poses[id] {
                    let r = poses.range(of: id)
                    let v = poses.speed(of: id)
                    HStack {
                        Circle()
                            .fill(nodeColor(id))
                            .frame(width: 7, height: 7)
                        Text(id).font(.caption)
                        Spacer()
                        Text(String(format: "%.2f %.2f %.2f  %.2fm  %.2fm/s", p.position.x, p.position.y, p.position.z, r, v))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Text("Input \(audio.inputChannelCount) ch  ·  Output \(audio.outputChannelCount) ch  ·  level \(audio.inputLevel, specifier: "%.3f")")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var nodeIDs: [String] {
        var ids = ["Mac", "Mac-L", "Mac-R", "Mac-MicL", "Mac-MicC", "Mac-MicR"]
        if poses.useCompanions {
            ids.append(contentsOf: ["iPhone", "AirPods"])
        }
        return ids
    }

    private func nodeColor(_ id: String) -> Color {
        if id.hasPrefix("Mac-Mic") { return Color.green }
        if id == "Mac-L" || id == "Mac-R" { return Color.orange }
        if id == "Mac" { return Color.white }
        if id == "iPhone" { return Color.cyan }
        return Color.yellow
    }

    private var peaks: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Last peaks").font(.headline)
            if audio.lastPeaks.isEmpty && !simulate {
                Text("No matched-filter peaks yet.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Array(audio.lastPeaks.prefix(8).enumerated()), id: \.offset) { _, p in
                let metres = Atmosphere.speedOfSound(celsius: temperature) * p.delaySeconds
                Text(String(format: "%@→%@  τ %.2f ms  %.2f m  snr %.2f", p.transmitterID, p.receiverID, p.delaySeconds * 1000, metres, p.snr))
                    .font(.system(.caption, design: .monospaced))
            }
        }
    }

    private var footer: some View {
        Text("\(hops) hops  ·  \(poses.arraySummary)  ·  18–21 kHz orthogonal  ·  GPS ungenutzt")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func fire() {
        let now = Date()
        let dt = min(1, max(0.12, now.timeIntervalSince(last)))
        last = now
        let c = Atmosphere.speedOfSound(celsius: temperature)
        poses.stepTruth(dt: dt)
        if simulate {
            let peaks = RoomSimulator.peaks(from: poses.truthList, c: c, airpodsTX: true)
            audio.lastPeaks = peaks
            poses.track(peaks: peaks, c: c, dt: dt)
            grid.integrate(peaks: peaks, poses: poses.poses, c: c)
            hops += 1
            if poses.useCompanions {
                status = String(format: "Auto-Track · iPhone %.2f m  AirPods %.2f m  · %d Peaks", poses.range(of: "iPhone"), poses.range(of: "AirPods"), peaks.count)
            } else {
                status = String(format: "Mac-Array · %d TX/RX-Paare  ·  %d Peaks  ·  kein iPhone", pairCount(peaks), peaks.count)
            }
            refreshField()
        } else {
            status = "Live ping…"
            Task {
                await audio.ping()
                poses.setArrayChannels(input: audio.inputChannelCount, output: audio.outputChannelCount)
                poses.track(peaks: audio.lastPeaks, c: c, dt: dt)
                grid.integrate(peaks: audio.lastPeaks, poses: poses.poses, c: c)
                hops += 1
                status = "Live ping · \(audio.lastPeaks.count) peaks · \(audio.outputChannelCount) out / \(audio.inputChannelCount) in."
                refreshField()
            }
        }
    }

    private func pairCount(_ peaks: [EchoPeak]) -> Int {
        Set(peaks.map { $0.transmitterID + "→" + $0.receiverID }).count
    }

    private func refreshField() {
        let lambda = Float(Atmosphere.speedOfSound(celsius: temperature) / 19_250)
        grid.recomputeField(poses: poses.list, wavelength: lambda)
    }
}
