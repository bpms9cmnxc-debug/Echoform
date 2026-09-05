# Echoform physics

## Atmosphere

Default conditions: 20 °C, 50 % relative humidity, 101.325 kPa.

\[
c = 331.3 + 0.606\,\vartheta_{\circ\mathrm{C}} \quad\mathrm{m/s}
\]

Temperature is the first-order term. Humidity and CO₂ are second-order indoors.

## Chirp

Linear frequency modulated pulse of duration \(T\), start \(f_0\), stop \(f_1\):

\[
s(t) = w(t)\sin\left(2\pi\left(f_0 t + \frac{f_1-f_0}{2T}t^2\right)\right),\quad 0\le t\le T
\]

\(w(t)\) is a Tukey window so the speaker is not slammed with a discontinuity. Default band 18.0–20.5 kHz at 48 kHz sample rate. That is the only band consumer 48 kHz I/O can both emit and Nyquist-sample with a few kHz of margin.

Mac-array mode splits the band: left speaker 18.0–19.5 kHz, right speaker 19.5–21.0 kHz, played in the same buffer. Orthogonal enough that a matched filter on each mic recovers both TX independently.

Time-bandwidth product \(TB = T(f_1-f_0)\) sets matched-filter compression. \(T = 8\,\mathrm{ms}\), \(B = 2.5\,\mathrm{kHz}\) → \(TB \approx 20\). Range resolution of the compressed pulse is on the order of

\[
\delta r \approx \frac{c}{2B} \approx 7\,\mathrm{cm}
\]

in the ideal monostatic case. Hardware and multipath make that optimistic.

## Matched filter

Recorded buffer \(r[n]\). Correlate against the known emitted chirp (zero-padded):

\[
R[k] = \sum_n r[n]\,s[n-k]
\]

Implemented as FFT multiply by the conjugate spectrum of \(s\). Peaks above a CFAR-ish threshold become candidate delays \(\tau = k / f_s\).

Direct path (speaker → mic, no wall) is the first strong peak and is discarded as a bounce. Subsequent peaks are multipath.

## Bistatic ellipse

Transmitter pose \(\mathbf{p}_t\), receiver pose \(\mathbf{p}_r\), delay \(\tau\):

\[
\|\mathbf{x}-\mathbf{p}_t\| + \|\mathbf{x}-\mathbf{p}_r\| = c\tau
\]

The locus of \(\mathbf{x}\) is an ellipsoid of revolution (ellipse in a slice). Occupancy is the accumulation of many such thin shells, weighted by peak SNR and pose covariance.

On a MacBook the two speakers are ~26 cm apart and the mics sit on the deck. Each wall echo therefore belongs to **two** slightly different ellipsoids (Mac-L→mic and Mac-R→mic). Their intersection is a curve; stacking many echoes fills the room without a second device.

## Interference field

The live 2D slice is not the map. It is the instantaneous pressure amplitude of the current chirp (or a CW tone at the chirp centre) evaluated on a grid:

\[
P(\mathbf{x}) = \sum_i \frac{A_i}{\|\mathbf{x}-\mathbf{p}_i\|}\exp\!\left(j(k\|\mathbf{x}-\mathbf{p}_i\|+\phi_i)\right)
\]

Bright = constructive, dark = destructive. Useful as a teaching overlay and as a sanity check that device poses are not nonsense. It is not an image of the furniture.

## Why GPS is unused

Civilian GNSS indoors is 5–15 m when it locks at all. Acoustic baselines here are centimetres to a few metres. Mixing GNSS into the pose graph would smear the cloud. UWB / Nearby Interaction (when both peers have a U1/U2-class chip and a session) is the correct scale. Visual-inertial / motion is the fallback.

## Why AirPods are a poor ToF node

Classic Bluetooth audio latency is 100–200 ms with jitter. 1 ms of unmodelled delay is 34 cm of path error. AirPods Pro have better spatial audio clocks than old Beats, but they are still not word-clocked to the Mac’s I/O. Echoform will use them if you select them; the mapper inflates their covariance so they do not wreck the grid.
