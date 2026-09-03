# Echoform

Multi-band near-ultrasonic echolocation for Mac / iPhone / AirPods.

Version 0.2: four simultaneous orthogonal chirps (8.5–10.5, 16.5–18, 18–19.5, 19.5–21 kHz), time-domain matched filter, cell-averaging CFAR + NMS, cross-band fusion, occupancy decay, alpha-beta scatterer tracks. GPS unused.

Repo: https://github.com/bpms9cmnxc-debug/Echoform

## Bugs fixed in 0.2

- Packed-real FFT correlation returned garbage lags (direct matched filter).
- Peak picker fired on neighbouring samples (CFAR + NMS).
- Sequential hops shorter than max ToF leaked into the next band as fake walls (simultaneous overlay).
- Live ping raced the mic tap (recording gate).
- Pose IDs did not match peak keys.
- Occupancy only appended voxels (decay + local maxima).
- No association (TrackBank).

## Build (macOS)

Open Echoform.xcodeproj or run Scripts/make_dmg.sh. Apple silicon, macOS 26/27. MIT.
