import SwiftUI
import simd

struct ContentView: View {
    @StateObject private var audio = AudioHub()
    @StateObject private var poses = PoseGraph()
    @StateObject private var grid = OccupancyGrid()
    @State private var simulate = true
    @State private var temperature = 20.0
    @State private var status = "Idle."

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

            VStack(spacing: 10) {
                CloudView(voxels: grid.voxels, poses: poses.list)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                FieldView(field: grid.field, width: grid.fieldWidth, height: grid.fieldHeight)
                    .frame(height: 180)
                    .overlay(alignment: .topLeading) {
                        Text("Interference slice  ·  constructive / destructive")
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
            refreshField()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ECHOFORM")
                .font(.system(size: 22, weight: .semibold, design: .monospaced))
            Text("Near-ultrasonic occupancy  ·  not LiDAR")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Simulation room (honest default)", isOn: $simulate)
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
                    status = "Grid cleared."
                }
            }
            .buttonStyle(.borderedProminent)
            Slider(value: $temperature, in: 10...30, step: 0.5) {
                Text("Air °C \(temperature, specifier: "%.1f")")
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
            ForEach(audio.devices) { d in
                HStack {
                    Circle().fill(d.hasInput && d.hasOutput ? Color.green : Color.orange).frame(width: 7, height: 7)
                    Text(d.name).font(.caption)
                }
            }
            Text("Input level \(audio.inputLevel, specifier: "%.3f")")
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack {
                Button("iPhone −") { poses.nudge("iPhone", by: SIMD3(-0.1, 0, 0)); refreshField() }
                Button("iPhone +") { poses.nudge("iPhone", by: SIMD3(0.1, 0, 0)); refreshField() }
            }
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
                Text(String(format: "τ %.3f ms   path %.2f m   snr %.2f", p.delaySeconds * 1000, metres, p.snr))
                    .font(.system(.caption, design: .monospaced))
            }
        }
    }

    private var footer: some View {
        Text("18–20.5 kHz chirp  ·  GPS unused  ·  UWB when the peer exists  ·  AirPods high covariance")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func fire() {
        let c = Atmosphere.speedOfSound(celsius: temperature)
        if simulate {
            let peaks = RoomSimulator.peaks(from: poses.list, c: c)
            audio.lastPeaks = peaks
            grid.integrate(peaks: peaks, poses: poses.poses, c: c)
            status = "Simulated ping · \(peaks.count) bistatic arrivals."
        } else {
            audio.ping()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                grid.integrate(peaks: audio.lastPeaks, poses: poses.poses, c: c)
                status = "Live ping · \(audio.lastPeaks.count) peaks. Treat ranges as noisy."
            }
        }
        refreshField()
    }

    private func refreshField() {
        let lambda = Float(Atmosphere.speedOfSound(celsius: temperature) / 19_250)
        grid.recomputeField(poses: poses.list, wavelength: lambda)
    }
}
