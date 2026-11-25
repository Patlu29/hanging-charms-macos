import AVFoundation
import HangingCharmsCore

/// Plays synthesised charm chimes. The engine starts on the first sound and stops after a
/// quiet spell, so a silent charm costs nothing.
@MainActor
final class AudioService {
    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayer = 0
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var buffers: [String: AVAudioPCMBuffer] = [:]
    private var lastPlayed = Date.distantPast
    private var idleTimer: Timer?

    var enabled = true
    var volume: Double = 0.6

    private static let voices = 4
    private static let minimumGap: TimeInterval = 0.07

    func play(_ material: SoundMaterial, intensity: Double) {
        guard enabled, volume > 0, intensity > 0.02 else { return }
        let now = Date()
        guard now.timeIntervalSince(lastPlayed) >= Self.minimumGap else { return }
        lastPlayed = now

        // Quantise intensity so buffers are reused rather than re-synthesised.
        let level = (min(1, intensity) * 8).rounded(.up) / 8
        let variation = Double.random(in: -0.02...0.02)
        let key = "\(material.rawValue)-\(level)-\(Int(variation * 100))"
        guard let buffer = buffers[key] ?? makeBuffer(material: material, level: level, variation: variation, key: key) else { return }

        startIfNeeded()
        guard !players.isEmpty else { return }
        let player = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        player.volume = Float(volume)
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        if !player.isPlaying { player.play() }
        scheduleIdleStop()
    }

    private func makeBuffer(material: SoundMaterial, level: Double, variation: Double, key: String) -> AVAudioPCMBuffer? {
        let samples = SoundSynthesizer.render(material: material, intensity: level, sampleRate: format.sampleRate, variation: variation)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            channel.update(from: source.baseAddress!, count: samples.count)
        }
        if buffers.count > 120 { buffers.removeAll() }
        buffers[key] = buffer
        return buffer
    }

    private func startIfNeeded() {
        if players.isEmpty {
            for _ in 0..<Self.voices {
                let player = AVAudioPlayerNode()
                engine.attach(player)
                engine.connect(player, to: engine.mainMixerNode, format: format)
                players.append(player)
            }
        }
        if !engine.isRunning {
            try? engine.start()
        }
    }

    private func scheduleIdleStop() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
    }

    func stop() {
        idleTimer?.invalidate()
        idleTimer = nil
        players.forEach { $0.stop() }
        if engine.isRunning { engine.stop() }
    }
}
