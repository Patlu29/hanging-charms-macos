import Foundation

/// Synthesises a charm's chime from decaying partials, so the app ships no audio files.
public enum SoundSynthesizer {
    public struct Partial: Sendable {
        public var ratio: Double
        public var amplitude: Double
        public var decay: Double
    }

    public static func partials(for material: SoundMaterial) -> (fundamental: Double, partials: [Partial]) {
        switch material {
        case .metal:
            (1320, [Partial(ratio: 1, amplitude: 0.6, decay: 7), Partial(ratio: 2.76, amplitude: 0.3, decay: 11), Partial(ratio: 5.4, amplitude: 0.15, decay: 16)])
        case .glass:
            (1760, [Partial(ratio: 1, amplitude: 0.55, decay: 9), Partial(ratio: 2.32, amplitude: 0.3, decay: 13), Partial(ratio: 4.25, amplitude: 0.18, decay: 20)])
        case .wood:
            (520, [Partial(ratio: 1, amplitude: 0.7, decay: 26), Partial(ratio: 2.1, amplitude: 0.25, decay: 34), Partial(ratio: 3.9, amplitude: 0.1, decay: 48)])
        case .ceramic:
            (980, [Partial(ratio: 1, amplitude: 0.6, decay: 14), Partial(ratio: 2.45, amplitude: 0.25, decay: 22), Partial(ratio: 4.8, amplitude: 0.12, decay: 30)])
        case .bell:
            (880, [Partial(ratio: 0.5, amplitude: 0.35, decay: 2.2), Partial(ratio: 1, amplitude: 0.5, decay: 3), Partial(ratio: 1.19, amplitude: 0.25, decay: 3.6), Partial(ratio: 2.0, amplitude: 0.2, decay: 5), Partial(ratio: 2.66, amplitude: 0.12, decay: 7)])
        }
    }

    /// Mono samples in -1...1.
    /// - Parameters:
    ///   - intensity: 0...1, from how hard the charm was knocked.
    ///   - variation: Small pitch variation so repeated knocks do not sound mechanical.
    public static func render(
        material: SoundMaterial,
        intensity: Double,
        sampleRate: Double = 44_100,
        variation: Double = 0
    ) -> [Float] {
        let (fundamental, partials) = partials(for: material)
        let level = min(max(intensity, 0), 1)
        let pitch = fundamental * (1 + min(max(variation, -0.05), 0.05))
        let slowest = partials.map(\.decay).min() ?? 5
        let duration = min(2.5, 6.9 / slowest) // ~-60 dB
        let count = Int(duration * sampleRate)
        let attack = 0.002 * sampleRate
        let total = partials.reduce(0) { $0 + $1.amplitude }

        var samples = [Float](repeating: 0, count: count)
        for index in 0..<count {
            let t = Double(index) / sampleRate
            var value = 0.0
            for partial in partials {
                value += partial.amplitude * exp(-partial.decay * t) * sin(2 * .pi * pitch * partial.ratio * t)
            }
            let envelope = Double(index) < attack ? Double(index) / attack : 1
            samples[index] = Float(value / total * envelope * level * 0.9)
        }
        return samples
    }
}
