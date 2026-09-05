# Hardware limitations (read this)

Echoform is built against the devices you actually own, not against a movie prop.

## Mac speakers and mics — this is enough for a 3D image

MacBook speakers are small, off-axis, and roll off hard in the top octave. Built-in mics are tuned for voice. You can put energy near 18–20 kHz; you cannot put a clean 40 kHz pulse into the room.

That is still enough. 14"/16" MacBook Pro hardware:

- Six speakers (force-cancelling woofers + tweeters) appear to Core Audio as **stereo**. Echoform drives them independently: left chirp 18–19.5 kHz, right chirp 19.5–21 kHz, same ping.
- Three-mic array. HAL often beamforms this down to one channel. Echoform records **every** input channel it is given. One mic + two speakers is already two intersecting bistatic ellipsoids (~26 cm baseline). USB interfaces with extra mics slot in as extra RX nodes.

The occupancy cloud is walls and large furniture as smeared sheets, generated from the laptop sitting on the desk. No iPhone, no AirPods, no UWB.

External USB interfaces with measurement mics change this immediately — Echoform enumerates them.

## iPhone (optional)

Better than a MacBook for this: more mics, known array geometry on Pro models, UWB chip from iPhone 11 onward, second-gen UWB from iPhone 15 onward (extended distance). Turn on **iPhone & AirPods** if you have one. The companion app is the right place for Nearby Interaction. Streaming raw 48 kHz PCM over the LAN is possible but wasteful; the phone should compress to peak lists.

## AirPods

Selectable as system input/output. Not a sync’d array. Treat as low-weight listener. When selected, Echoform falls back to a single TX/RX pair instead of the Mac array.

## UWB / Nearby Interaction on macOS

Apple documents Nearby Interaction primarily for iPhone, Watch, and MFi accessories. Some macOS Tahoe builds expose NISession; feature flags differ by chip. Echoform probes `NISession` at runtime and degrades to Multipeer + motion if the session cannot start.

## Clock sync

Without a shared word clock, cross-device ToF needs an estimate of one-way latency. Echoform measures the direct-path peak between a known speaker-mic pair on the *same* device (zero extra latency) and uses that as a local calibration. Cross-device pairs get a bias state in the pose graph. Mac-L → Mac-Mic is that calibration pair.

## What a “3D picture” means here

An occupancy grid and a coloured point cloud of likely scattering surfaces. Walls and large furniture can appear as smeared sheets. A face, a cable, a glass table edge will not. That is physics, not a missing feature.
