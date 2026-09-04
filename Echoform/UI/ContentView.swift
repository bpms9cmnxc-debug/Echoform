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
    @State private var status = "Auto-Track an."
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
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ECHOFORM")
                .font(.system(size: 22, weight: .semibold, design: .monospaced))
            Text("Native 3D  ·  Auto-Track aus Laufzeit  ·  kein HTML")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Simulation", isOn: $simulate)
            Toggle("Auto-Track", isOn: $auto)
            HStack {
                Button("Arm I/O") {
                    Task {
                        do {
                            try audio.arm()
                            status = "Engine running."
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
            ForEach(["Mac", "iPhone", "AirPods"], id: \.self) { id in
                if let p = poses.poses[id] {
                    let r = poses.range(of: id)
                    let v = poses.speed(of: id)
                    HStack {
                        Circle()
                            .fill(id == "Mac" ? Color.white : (id == "iPhone" ? Color.cyan : Color.yellow))
                            .frame(width: 7, height: 7)
                        Text(id).font(.caption)
                        Spacer()
                        Text(String(format: "%.2f %.2f %.2f  %.2fm  %.2fm/s", p.position.x, p.position.y, p.position.z, r, v))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Text("Input level \(audio.inputLevel, specifier: "%.3f")")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var peaks: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Last peaks").font(.headline)
            if audio.lastPeaks.isEmpty && !simulate {
                Text("No matched-filter peaks yet.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Array(audio.lastPeaks.prefix(6).enumerated()), id: \.offset) { _, p in
                let metres = Atmosphere.speedOfSound(celsius: temperature) * p.delaySeconds
                Text(String(format: "%@→%@  τ %.2f ms  %.2f m  snr %.2f", p.transmitterID, p.receiverID, p.delaySeconds * 1000, metres, p.snr))
                    .font(.system(.caption, design: .monospaced))
            }
        }
    }

    private var footer: some View {
        Text("\(hops) hops  ·  8.5–21 kHz  ·  AirPods nur TX  ·  GPS ungenutzt")
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
            status = String(format: "Auto-Track · iPhone %.2f m  AirPods %.2f m  · %d Peaks", poses.range(of: "iPhone"), poses.range(of: "AirPods"), peaks.count)
        } else {
            audio.ping()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                poses.track(peaks: audio.lastPeaks, c: c, dt: dt)
                grid.integrate(peaks: audio.lastPeaks, poses: poses.poses, c: c)
                hops += 1
                status = "Live ping · \(audio.lastPeaks.count) peaks."
            }
        }
        refreshField()
    }

    private func refreshField() {
        let lambda = Float(Atmosphere.speedOfSound(celsius: temperature) / 19_250)
        grid.recomputeField(poses: poses.list, wavelength: lambda)
    }
}
