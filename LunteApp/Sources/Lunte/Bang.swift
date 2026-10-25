import AVFoundation

/// The Boom out loud: a soft fizz, like the fuse's last hiss, then the bang. A faint sound 30–500 ms before a loud one
/// dampens the startle (prepulse inhibition), so the bang lands as a cartoon, not an alarm.
@MainActor
enum Bang {
    /// Seconds of fizz before the bang.
    // Why: a faint sound just before a loud one softens the startle (docs/why.md#prepulse-fizz)
    static let fizz = 0.4
    /// The cap on the whole sound, as a share of the Mac's volume. ponytail: fixed, no slider.
    // Why: a cartoon, not an alarm, or the sound gets switched off for good (docs/why.md#juice-inverted-u)
    private static let volume: Float = 0.6
    private static var engine: AVAudioEngine? // kept so it isn't freed mid-boom

    /// The fizz now and `boom.wav` right after it, queued back to back on one player, so the gap never drifts.
    static func play() {
        engine?.stop()
        guard let url = Bundle.main.url(forResource: "boom", withExtension: "wav"),
              let file = try? AVAudioFile(forReading: url),
              let bang = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: bang)) != nil else { return }
        let e = AVAudioEngine(), player = AVAudioPlayerNode()
        e.attach(player)
        e.connect(player, to: e.mainMixerNode, format: bang.format)
        player.volume = volume * (bang.format.channelCount == 1 ? Float(2).squareRoot() : 1) // the mixer puts mono 3 dB down a side
        player.scheduleBuffer(hiss(bang.format))
        player.scheduleBuffer(bang)
        guard (try? e.start()) != nil else { return }
        player.play()
        engine = e
        let seconds = fizz + Double(bang.frameLength) / bang.format.sampleRate + 0.5
        Task { try? await Task.sleep(for: .seconds(seconds)); if engine === e { e.stop(); engine = nil } } // lets the speakers sleep
    }

    /// `fizz` seconds of a fuse hissing: noise between about 2 and 8 kHz that sputters, far under the bang. It fades in,
    /// so it doesn't click, and swells a little into the bang.
    private static func hiss(_ format: AVAudioFormat) -> AVAudioPCMBuffer {
        let rate = format.sampleRate, frames = Int(fizz * rate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        buffer.frameLength = AVAudioFrameCount(frames)
        let pole = { (hz: Double) in Float(1 - exp(-2 * .pi * hz / rate)) }
        let (bright, dull) = (pole(8000), pole(2000))
        var a: Float = 0, b: Float = 0, sputter: Float = 1
        for i in 0..<frames {
            let white = Float.random(in: -1...1)
            a += bright * (white - a) // two low-passes; what's between them is the hiss
            b += dull * (white - b)
            if i % Int(rate / 100) == 0 { sputter = .random(in: 0.3...1) } // the fuse spits
            let t = Double(i) / rate
            let envelope = Float(min(1, t / 0.03, (fizz - t) / 0.01) * (0.5 + 0.5 * t / fizz))
            for c in 0..<Int(format.channelCount) { buffer.floatChannelData![c][i] = 0.1 * (a - b) * sputter * envelope }
        }
        return buffer
    }
}
