import SwiftUI

@main
struct USBCameraApp: App {
    @StateObject private var camera = CameraManager()

    var body: some Scene {
        WindowGroup("USB Camera") {
            ContentView()
                .environmentObject(camera)
                .frame(minWidth: 640, minHeight: 480)
        }
    }
}
