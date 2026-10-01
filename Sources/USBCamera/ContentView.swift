import SwiftUI

struct ContentView: View {
    @EnvironmentObject var camera: CameraManager

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                PreviewView(session: camera.session, mirrored: camera.mirrored)
                if camera.devices.isEmpty || !camera.authorized {
                    VStack(spacing: 8) {
                        Image(systemName: "video.slash").font(.system(size: 48))
                        Text(camera.status.isEmpty ? "找不到攝影機" : camera.status)
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(.white.opacity(0.8))
                    .padding()
                }
            }
            Divider()
            controls
        }
    }

    private var controls: some View {
        VStack(spacing: 8) {
            HStack {
                Picker("攝影機", selection: $camera.selectedDeviceID) {
                    ForEach(camera.devices, id: \.uniqueID) { d in
                        Text(d.localizedName).tag(Optional(d.uniqueID))
                    }
                }
                .frame(maxWidth: 300)

                Picker("解析度", selection: $camera.selectedFormatID) {
                    ForEach(camera.formats) { f in
                        Text(f.label).tag(Optional(f.id))
                    }
                }
                .frame(maxWidth: 300)

                Button { camera.refreshDevices() } label: { Image(systemName: "arrow.clockwise") }
                    .help("重新偵測裝置")
            }
            HStack {
                Toggle("鏡像", isOn: $camera.mirrored)
                Spacer()
                Button { camera.takePhoto() } label: { Label("拍照", systemImage: "camera") }
                    .disabled(camera.devices.isEmpty)
                Button { camera.toggleRecording() } label: {
                    Label(camera.isRecording ? "停止錄影" : "錄影",
                          systemImage: camera.isRecording ? "stop.circle.fill" : "record.circle")
                        .foregroundStyle(camera.isRecording ? .red : .primary)
                }
                .disabled(camera.devices.isEmpty)
                Button { camera.revealFolder() } label: { Label("開啟資料夾", systemImage: "folder") }
            }
            HStack {
                Text(camera.status).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
            }
        }
        .padding(12)
    }
}
