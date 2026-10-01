@preconcurrency import AVFoundation
import AppKit

struct CameraFormat: Identifiable, Hashable {
    let id: String
    let label: String
    let format: AVCaptureDevice.Format

    static func == (l: CameraFormat, r: CameraFormat) -> Bool { l.id == r.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

@MainActor
final class CameraManager: NSObject, ObservableObject {
    @Published var devices: [AVCaptureDevice] = []
    @Published var selectedDeviceID: String? {
        didSet { if oldValue != selectedDeviceID { configureSession() } }
    }
    @Published var formats: [CameraFormat] = []
    @Published var selectedFormatID: String? {
        didSet { applyFormat() }
    }
    @Published var authorized = false
    @Published var isRecording = false
    @Published var mirrored = false
    @Published var status = ""

    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    private var observers: [NSObjectProtocol] = []

    override init() {
        super.init()
        // 關閉 Center Stage（它會在本行程內跑人臉偵測，吃 CPU / ANE）
        AVCaptureDevice.centerStageControlMode = .app
        AVCaptureDevice.isCenterStageEnabled = false
        let nc = NotificationCenter.default
        for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refreshDevices() }
            })
        }
        requestAccess()
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    // MARK: - 權限與裝置

    private func requestAccess() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            authorized = true
            refreshDevices()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] ok in
                Task { @MainActor in
                    self?.authorized = ok
                    if ok { self?.refreshDevices() }
                }
            }
        default:
            authorized = false
            status = "未取得攝影機權限，請至「系統設定 > 隱私權與安全性 > 攝影機」開啟。"
        }
    }

    func refreshDevices() {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external, .builtInWideAngleCamera],
            mediaType: .video,
            position: .unspecified)
        devices = discovery.devices
        if let id = selectedDeviceID, devices.contains(where: { $0.uniqueID == id }) { return }
        // 優先選擇外接（USB）攝影機
        selectedDeviceID = (devices.first { $0.deviceType == .external } ?? devices.first)?.uniqueID
        if devices.isEmpty {
            session.stopRunning()
            formats = []
            status = "找不到攝影機，請接上 USB 攝影機。"
        }
    }

    private var currentDevice: AVCaptureDevice? {
        devices.first { $0.uniqueID == selectedDeviceID }
    }

    // MARK: - Session

    private func configureSession() {
        if isRecording { stopRecording() }
        session.beginConfiguration()
        session.inputs.forEach(session.removeInput)
        session.outputs.forEach(session.removeOutput)

        guard let device = currentDevice, let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)
        session.commitConfiguration()

        loadFormats(for: device)
        status = device.localizedName
        let s = session
        DispatchQueue.global(qos: .userInitiated).async { if !s.isRunning { s.startRunning() } }
    }

    private func loadFormats(for device: AVCaptureDevice) {
        var seen = Set<String>()
        var list: [CameraFormat] = []
        for f in device.formats {
            let d = CMVideoFormatDescriptionGetDimensions(f.formatDescription)
            let maxFPS = Int(f.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0)
            let key = "\(d.width)x\(d.height)@\(maxFPS)"
            guard seen.insert(key).inserted else { continue }
            list.append(CameraFormat(id: key, label: "\(d.width) × \(d.height) @ \(maxFPS)fps", format: f))
        }
        list.sort {
            let a = CMVideoFormatDescriptionGetDimensions($0.format.formatDescription)
            let b = CMVideoFormatDescriptionGetDimensions($1.format.formatDescription)
            return a.width * a.height > b.width * b.height
        }
        formats = list
        // 預設挑 720p（解碼與 CPU 負擔最低且夠用），沒有就沿用目前格式
        let preferred = list.filter {
            CMVideoFormatDescriptionGetDimensions($0.format.formatDescription).height == 720
        }.min { abs(maxFPS($0) - 30) < abs(maxFPS($1) - 30) }
        if let preferred {
            selectedFormatID = preferred.id
        } else {
            let active = device.activeFormat
            let d = CMVideoFormatDescriptionGetDimensions(active.formatDescription)
            selectedFormatID = "\(d.width)x\(d.height)@\(maxFPS(active))"
        }
    }

    private func maxFPS(_ f: CameraFormat) -> Int { maxFPS(f.format) }
    private func maxFPS(_ f: AVCaptureDevice.Format) -> Int {
        Int(f.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0)
    }

    private func applyFormat() {
        guard let device = currentDevice,
              let item = formats.first(where: { $0.id == selectedFormatID }),
              device.activeFormat != item.format else { return }
        do {
            try device.lockForConfiguration()
            device.activeFormat = item.format
            device.unlockForConfiguration()
        } catch {
            status = "無法切換解析度：\(error.localizedDescription)"
        }
    }

    // MARK: - 拍照 / 錄影

    private var outputDirectory: URL {
        FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("USBCamera", isDirectory: true)
    }

    private func newFileURL(ext: String) -> URL {
        try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return outputDirectory.appendingPathComponent("\(f.string(from: Date())).\(ext)")
    }

    /// 暫時把輸出（與麥克風）接上 session，用完即移除，預覽時不付出額外成本。
    private func attach(_ output: AVCaptureOutput, audio: Bool = false) -> Bool {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        if audio, AVCaptureDevice.authorizationStatus(for: .audio) != .denied,
           let mic = AVCaptureDevice.default(for: .audio),
           let input = try? AVCaptureDeviceInput(device: mic), session.canAddInput(input) {
            session.addInput(input)
        }
        guard session.canAddOutput(output) else { return false }
        session.addOutput(output)
        return true
    }

    private func detach(_ output: AVCaptureOutput) {
        session.beginConfiguration()
        session.removeOutput(output)
        for input in session.inputs where (input as? AVCaptureDeviceInput)?.device.hasMediaType(.audio) == true {
            session.removeInput(input)
        }
        session.commitConfiguration()
    }

    func takePhoto() {
        guard session.isRunning, attach(photoOutput) else { return }
        photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
    }

    func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        guard session.isRunning, !movieOutput.isRecording else { return }
        guard attach(movieOutput, audio: true) else { return }
        movieOutput.startRecording(to: newFileURL(ext: "mov"), recordingDelegate: self)
        isRecording = true
    }

    private func stopRecording() {
        if movieOutput.isRecording { movieOutput.stopRecording() }
        isRecording = false
    }

    func revealFolder() {
        try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(outputDirectory)
    }
}

extension CameraManager: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = photo.fileDataRepresentation()
        Task { @MainActor in
            self.detach(self.photoOutput)
            guard error == nil, let data else {
                self.status = "拍照失敗：\(error?.localizedDescription ?? "無資料")"
                return
            }
            let url = self.newFileURL(ext: "jpg")
            do {
                try data.write(to: url)
                self.status = "已儲存照片：\(url.lastPathComponent)"
            } catch {
                self.status = "儲存失敗：\(error.localizedDescription)"
            }
        }
    }
}

extension CameraManager: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo url: URL, from connections: [AVCaptureConnection], error: Error?) {
        Task { @MainActor in
            self.isRecording = false
            self.detach(self.movieOutput)
            self.status = "已儲存影片：\(url.lastPathComponent)"
        }
    }
}
