# Hardware limitations (read this)

Echoform is built against the devices you actually own, not against a movie prop.

## Mac speakers and mics

MacBook speakers are small, off-axis, and roll off hard in the top octave. Built-in mics are tuned for voice. You can put energy near 18–20 kHz; you cannot put a clean 40 kHz pulse into the room. External USB interfaces with measurement mics change this immediately — Echoform enumerates them.

## iPhone

Better than a MacBook for this: more mics, known array geometry on Pro models, UWB chip from iPhone 11 onward, second-gen UWB from iPhone 15 onward (extended distance). The companion app is the right place for Nearby Interaction. Streaming raw 48 kHz PCM over the LAN is possible but wasteful; the phone should compress to peak lists.

## AirPods

Selectable as system input/output. Not a sync’d array. Treat as low-weight listener.

## UWB / Nearby Interaction on macOS

Apple documents Nearby Interaction primarily for iPhone, Watch, and MFi accessories. Some macOS Tahoe builds expose NISession; feature flags differ by chip. Echoform probes `NISession` at runtime and degrades to Multipeer + motion if the session cannot start.

## Clock sync

Without a shared word clock, cross-device ToF needs an estimate of one-way latency. Echoform measures the direct-path peak between a known speaker-mic pair on the *same* device (zero extra latency) and uses that as a local calibration. Cross-device pairs get a bias state in the pose graph.

## What a “3D picture” means here

An occupancy grid and a coloured point cloud of likely scattering surfaces. Walls and large furniture can appear as smeared sheets. A face, a cable, a glass table edge will not. That is physics, not a missing feature.
