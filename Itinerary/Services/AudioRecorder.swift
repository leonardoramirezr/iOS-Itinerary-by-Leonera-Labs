import AVFoundation
import Foundation
import Observation

/// Records the dictation to a compact AAC file that is sent to the speech to text API.
@MainActor
@Observable
final class AudioRecorder {
    private(set) var isRecording = false
    private(set) var elapsed: TimeInterval = 0
    /// Normalized input level between 0 and 1, used for the recording animation.
    private(set) var level: Float = 0

    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var fileURL: URL?

    func start() async throws {
        guard await AVAudioApplication.requestRecordPermission() else {
            throw AppError.microphoneDenied
        }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .default)
        try session.setActive(true)

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dictation-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16_000.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = true
        guard recorder.record() else { throw AppError.recordingFailed }

        self.recorder = recorder
        fileURL = url
        elapsed = 0
        level = 0
        isRecording = true
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateMeters()
            }
        }
    }

    /// Stops the recording and returns the audio file.
    func stop() -> URL? {
        guard isRecording else { return nil }
        recorder?.stop()
        finish()
        return fileURL
    }

    /// Stops the recording and deletes the audio file.
    func cancel() {
        guard isRecording else { return }
        recorder?.stop()
        recorder?.deleteRecording()
        finish()
        fileURL = nil
    }

    private func finish() {
        timer?.invalidate()
        timer = nil
        recorder = nil
        isRecording = false
        level = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func updateMeters() {
        guard let recorder else { return }
        recorder.updateMeters()
        elapsed = recorder.currentTime
        let decibels = recorder.averagePower(forChannel: 0)
        level = max(0, min(1, (decibels + 50) / 50))
    }
}
