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
    @Published var volume: Double = UserDefaults.standard.object(forKey: "GeroAudio.volume") as? Double ?? 0.0 { didSet { playerNode.volume = Float(volume); UserDefaults.standard.set(volume, forKey: "GeroAudio.volume") } }
    private let eqFrequencies: [Float] = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    @Published var eqEnabled: Bool = UserDefaults.standard.object(forKey: "GeroAudio.eqEnabled") as? Bool ?? false {
        didSet { applyEQ(); UserDefaults.standard.set(eqEnabled, forKey: "GeroAudio.eqEnabled") }
    }
    @Published var eqGains: [Double] = (0..<10).map { UserDefaults.standard.double(forKey: "GeroAudio.eqGain.\($0)") } {
        didSet {
            applyEQ()
            for index in 0..<min(eqGains.count, 10) {
                UserDefaults.standard.set(eqGains[index], forKey: "GeroAudio.eqGain.\(index)")
            }
        }
    }

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let equalizer = AVAudioUnitEQ(numberOfBands: 10)
    private var timer: Timer?
    private var currentFile: AVAudioFile?
    private var queue: [Track] = []
    private var currentIndex = 0
    private var playbackOffset: TimeInterval = 0
    private var playbackGeneration: UInt64 = 0

    init() {
        engine.attach(playerNode)
        engine.attach(equalizer)
        engine.connect(playerNode, to: equalizer, format: nil)
        engine.connect(equalizer, to: engine.mainMixerNode, format: nil)
        equalizer.globalGain = 0
        for (index, band) in equalizer.bands.enumerated() {
            band.filterType = .parametric
            band.frequency = eqFrequencies[index]
            band.bandwidth = 1.0
            band.gain = Float(eqGains[index])
            band.bypass = !eqEnabled
        }
        playerNode.volume = Float(volume)
        refreshOutputs()
    }

    func setEQGain(_ gain: Double, for index: Int) {
        guard eqGains.indices.contains(index) else { return }
        var updated = eqGains
        updated[index] = min(12, max(-12, gain))
        eqGains = updated
    }

    func resetEQ() {
        eqGains = Array(repeating: 0, count: 10)
    }

    private func applyEQ() {
        guard equalizer.bands.count == 10 else { return }
        for index in 0..<10 {
            equalizer.bands[index].gain = Float(eqGains[index])
            equalizer.bands[index].bypass = !eqEnabled
        }
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

    func play(_ track: Track, queue newQueue: [Track]? = nil) {
        if let newQueue, !newQueue.isEmpty {
            queue = newQueue
            currentIndex = queue.firstIndex(of: track) ?? 0
        } else {
            queue = [track]
            currentIndex = 0
        }
        startCurrentTrack(at: 0)
    }

    private func startCurrentTrack(at position: TimeInterval) {
        guard queue.indices.contains(currentIndex) else { return }
        let track = queue[currentIndex]
        playbackGeneration &+= 1
        let generation = playbackGeneration
        do {
            playerNode.stop()
            timer?.invalidate()
            let file = try AVAudioFile(forReading: track.url)
            currentFile = file
            currentTrack = track
            let safePosition = min(max(0, position), max(0, track.duration))
            playbackOffset = safePosition
            elapsed = safePosition
            if !engine.isRunning { try engine.start() }
            let startFrame = AVAudioFramePosition((track.startTime + safePosition) * file.processingFormat.sampleRate)
            let segmentEnd = min(Double(file.length) / file.processingFormat.sampleRate, track.endTime ?? (Double(file.length) / file.processingFormat.sampleRate))
            let endFrame = AVAudioFramePosition(segmentEnd * file.processingFormat.sampleRate)
            let remainingFrames = max(0, endFrame - startFrame)
            guard remainingFrames > 0 else {
                if !nextTrack() { isPlaying = false }
                return
            }
            let frameCount = AVAudioFrameCount(min(Int64(UInt32.max), remainingFrames))
            playerNode.scheduleSegment(file, startingFrame: startFrame, frameCount: frameCount, at: nil) { [weak self] in
                Task { @MainActor in
                    guard let self, self.playbackGeneration == generation else { return }
                    if !self.nextTrack() {
                        self.isPlaying = false
                        self.timer?.invalidate()
                    }
                }
            }
            playerNode.play()
            isPlaying = true
            startTimer()
        } catch {
            isPlaying = false
            print("GeroAudio playback error: \(error)")
        }
    }

    @discardableResult
    func nextTrack() -> Bool {
        guard currentIndex + 1 < queue.count else { return false }
        currentIndex += 1
        startCurrentTrack(at: 0)
        return true
    }

    @discardableResult
    func previousTrack() -> Bool {
        if elapsed > 3 {
            seek(to: 0)
            return true
        }
        guard currentIndex > 0 else {
            seek(to: 0)
            return true
        }
        currentIndex -= 1
        startCurrentTrack(at: 0)
        return true
    }

    func seek(to position: TimeInterval) {
        guard currentFile != nil, currentTrack != nil else { return }
        let wasPlaying = isPlaying
        playerNode.stop()
        startCurrentTrack(at: position)
        if !wasPlaying { pause() }
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
        playbackGeneration &+= 1
        playerNode.stop()
        isPlaying = false
        elapsed = 0
        playbackOffset = 0
        timer?.invalidate()
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isPlaying, let nodeTime = self.playerNode.lastRenderTime,
                      let playerTime = self.playerNode.playerTime(forNodeTime: nodeTime) else { return }
                self.elapsed = self.playbackOffset + Double(playerTime.sampleTime) / playerTime.sampleRate
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
