# iPhone companion (next target)

The Mac app is the mapper. The useful UWB node is the iPhone.

Add an iOS target in the same project when you open it in Xcode 27:

1. New target → App → EchoformPhone, bundle `app.echoform.phone`.
2. Entitlements: Nearby Interaction, microphone, local network.
3. Share `ChirpSynth`, `MatchedFilter`, `Units` via a local Swift package.
4. Start `NISession`, exchange `discoveryToken` over Multipeer (`_echoform._tcp`).
5. Do not stream raw PCM. Send `EchoPeak` JSON.

AirPods stay a system I/O device on whichever host they are attached to. They do not run this target.
