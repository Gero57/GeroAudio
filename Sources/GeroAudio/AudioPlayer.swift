import Foundation
import AVFoundation
import CoreAudio
import AudioToolbox
import Combine

struct AudioOutput: Identifiable, Hashable {
    let id: AudioDeviceID
    let name: String
}

@MainActor
final class AudioPlayer: ObservableObject {
    @Published private(set) var currentTrack: Track?
    @Published private(set) var isPlaying = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var outputs: [AudioOutput] = []
    @Published var selectedOutputID: AudioDeviceID?
    @Published var volume: Double = 0.85 { didSet { playerNode.volume = Float(volume) } }

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var timer: Timer?
    private var currentFile: AVAudioFile?

    init() {
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: nil)
        refreshOutputs()
    }

    func refreshOutputs() {
        outputs = Self.outputDevices()
        if selectedOutputID == nil { selectedOutputID = outputs.first?.id }
    }

    func selectOutput(_ id: AudioDeviceID?) {
        guard let id, let unit = engine.outputNode.audioUnit else { return }
        var device = id
        let status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice,
                                          kAudioUnitScope_Global, 0, &device,
                                          UInt32(MemoryLayout<AudioDeviceID>.size))
        if status == noErr { selectedOutputID = id }
    }

    func play(_ track: Track) {
        do {
            playerNode.stop()
            let file = try AVAudioFile(forReading: track.url)
            currentFile = file
            currentTrack = track
            elapsed = 0
            if !engine.isRunning { try engine.start() }
            playerNode.scheduleFile(file, at: nil) { [weak self] in
                Task { @MainActor in self?.isPlaying = false; self?.timer?.invalidate() }
            }
            playerNode.play()
            isPlaying = true
            startTimer()
        } catch {
            isPlaying = false
            print("GeroAudio playback error: \(error)")
        }
    }

    func togglePlayback() {
        if isPlaying { pause() } else { resume() }
    }

    func pause() {
        playerNode.pause()
        isPlaying = false
        timer?.invalidate()
    }

    func resume() {
        guard currentFile != nil else { return }
        do {
            if !engine.isRunning { try engine.start() }
            playerNode.play()
            isPlaying = true
            startTimer()
        } catch { print("GeroAudio engine error: \(error)") }
    }

    func stop() {
        playerNode.stop()
        isPlaying = false
        elapsed = 0
        timer?.invalidate()
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isPlaying, let nodeTime = self.playerNode.lastRenderTime,
                      let playerTime = self.playerNode.playerTime(forNodeTime: nodeTime),
                      let file = self.currentFile else { return }
                self.elapsed = Double(playerTime.sampleTime) / playerTime.sampleRate
                if self.elapsed >= Double(file.length) / file.processingFormat.sampleRate {
                    self.isPlaying = false
                    self.timer?.invalidate()
                }
            }
        }
    }

    static func outputDevices() -> [AudioOutput] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            var outputAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                                           mScope: kAudioDevicePropertyScopeOutput,
                                                           mElement: kAudioObjectPropertyElementMain)
            var outputSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &outputAddress, 0, nil, &outputSize) == noErr, outputSize > 0 else { return nil }
            var nameAddress = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
                                                         mScope: kAudioObjectPropertyScopeGlobal,
                                                         mElement: kAudioObjectPropertyElementMain)
            var name: CFString = "Audio Device" as CFString
            var nameSize = UInt32(MemoryLayout<CFString>.size)
            let status = AudioObjectGetPropertyData(id, &nameAddress, 0, nil, &nameSize, &name)
            return AudioOutput(id: id, name: status == noErr ? name as String : "Audio Device")
        }
    }
}
