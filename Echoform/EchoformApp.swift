import SwiftUI

@main
struct EchoformApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 980, minHeight: 640)
        }
        .windowStyle(.automatic)
        .defaultSize(width: 1180, height: 740)
    }
}
