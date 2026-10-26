import AVFoundation

/// The flame's voice, synthesised, following a `FuseScene.Voice`: noise between two low-passes that rise with the pitch,
/// sputtering as a fuse spits, crackling more the hotter it burns, and a breath of low noise for the smoke. Everything
/// glides, so a voice set once a frame never clicks. Its noise is seeded, so the renders sound like the app. Given a
/// `Recording`, it plays a real fuse instead, as the app does (`fuse.wav`), and given a `puff`, a real puff as the flame
/// goes out in place of the breath of noise.
public struct FlameSynth {
    public var voice = FuseScene.Voice()
    /// A real fuse in place of the noise, or nil for the synth.
    public var recording: Recording?
    /// A real puff as it goes out (`puff.wav`), or nil for a breath of low noise.
    public var puff: [Float]?

    /// A real fuse: `calm` and `hot` looping under the flame, crossfaded by how hot it burns, one loop or two, and
    /// `catching` as a burn lights, if there's one. Mono, levelled so `calm` at a sizzle of 1 is as loud as the synth.
    public struct Recording {
        public var catching: [Float], calm: [Float], hot: [Float]

        public init(catching: [Float] = [], calm: [Float], hot: [Float]) { (self.catching, self.calm, self.hot) = (catching, calm, hot) }

        /// The pieces from mono files at the synth's rate, `hot` the same as `calm` unless given, or nil if one won't read.
        public init?(catching: URL? = nil, calm: URL, hot: URL? = nil) {
            guard let b = FlameSynth.read(calm), let c = hot.map(FlameSynth.read) ?? b else { return nil }
            self.init(catching: catching.flatMap(FlameSynth.read) ?? [], calm: b, hot: c)
        }
    }

    /// A sound file's first channel, at the rate it was made, or nil if it won't read.
    public static func read(_ url: URL) -> [Float]? {
        guard let file = try? AVAudioFile(forReading: url),
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buffer)) != nil, let data = buffer.floatChannelData else { return nil }
        return Array(UnsafeBufferPointer(start: data[0], count: Int(buffer.frameLength)))
    }
    /// The sizzle at full, as a share of full scale.
    public static let level: Float = 0.1
    private let rate: Double
    private var sizzle = 0.0, pitch = 1.0, crackle = 0.0, smoke = 0.0
    private var hi: Float = 0, lo: Float = 0, dark: Float = 0, sputter: Float = 1, pop: Float = 0
    private var bands: (hi: Float, lo: Float, dark: Float) = (0, 0, 0)
    private var rng: UInt64 = 0x2545_f491_4f6c_dd1d, n = 0
    private var calmAt = 0.0, hotAt = 0.0, catchAt: Double?, puffAt: Double?, flared = 0.0, puffed = 0.0

    public init(rate: Double) { self.rate = rate }

    /// The next `count` samples of the voice, at `gain`, into `out`.
    public mutating func render(_ count: Int, gain: Float, into out: UnsafeMutablePointer<Float>) {
        if voice.smoke > 0.2, puffed < 0.05, puff != nil { puffAt = 0 } // the flame goes out
        puffed = voice.smoke
        if let recording { return play(recording, count, gain: gain, into: out) }
        let glide = 1 - exp(-1 / (0.04 * rate)) // 40 ms
        let breath: Float = puff == nil ? 1.3 : 0
        for i in 0..<count {
            sizzle += (voice.sizzle - sizzle) * glide
            pitch += (voice.pitch - pitch) * glide
            crackle += (voice.crackle - crackle) * glide
            smoke += (voice.smoke - smoke) * glide
            if n % 64 == 0 { bands = (pole(6500 * pitch), pole(1800 * pitch), pole(700)) }
            let white = random()
            hi += bands.hi * (white - hi) // two low-passes; what's between them is the hiss
            lo += bands.lo * (white - lo)
            dark += bands.dark * (white - dark) // and a low one, the smoke's breath
            if n % Int(rate / 110) == 0 { sputter = 1 - Float(0.25 + 0.5 * crackle) * (random() + 1) / 2 } // the fuse spits
            if (random() + 1) / 2 < Float(crackle * crackle) * 0.0006 { pop = 1 } // a crackle, some 25 a second when hot
            pop *= 0.96
            out[i] = gain * (Self.level * (Float(sizzle) * (hi - lo) * (sputter + 3 * pop) + breath * Float(smoke) * dark) + nextPuff(pitch))
            n += 1
        }
    }

    /// The recording's way: the loops under the flame, the catch when a burn flares, the puff when it goes out.
    private mutating func play(_ r: Recording, _ count: Int, gain: Float, into out: UnsafeMutablePointer<Float>) {
        if voice.flare > 0.8, flared < 0.5, r.catching.count > 1 { catchAt = 0 } // a burn catches
        flared = voice.flare
        let glide = 1 - exp(-1 / (0.04 * rate)), lift = Float(0.5 + 0.5 * voice.crackle)
        func at(_ x: [Float], _ p: Double) -> Float { // between two samples, as it plays faster or slower
            let k = Int(p) % x.count, f = Float(p - p.rounded(.down))
            return x[k] * (1 - f) + x[(k + 1) % x.count] * f
        }
        for i in 0..<count {
            sizzle += (voice.sizzle - sizzle) * glide
            pitch += (voice.pitch - pitch) * glide
            crackle += (voice.crackle - crackle) * glide
            let h = Float(min(1, max(0, (crackle - 0.3) / 0.6))) // calm, then hot as it nears the end
            var o = Float(sizzle) * ((1 - h).squareRoot() * at(r.calm, calmAt) + h.squareRoot() * at(r.hot, hotAt))
            if let c = catchAt { o += lift * at(r.catching, c); catchAt = c + pitch < Double(r.catching.count - 1) ? c + pitch : nil }
            calmAt = (calmAt + pitch).truncatingRemainder(dividingBy: Double(r.calm.count))
            hotAt = (hotAt + pitch).truncatingRemainder(dividingBy: Double(r.hot.count))
            out[i] = gain * (o + nextPuff(pitch))
        }
    }

    /// The next sample of the puff, if it's puffing.
    private mutating func nextPuff(_ pitch: Double) -> Float {
        guard let puff, let p = puffAt else { return 0 }
        let k = Int(p), f = Float(p - Double(k))
        puffAt = p + pitch < Double(puff.count - 1) ? p + pitch : nil
        return puff[k] * (1 - f) + puff[min(k + 1, puff.count - 1)] * f
    }

    private func pole(_ hz: Double) -> Float { Float(1 - exp(-2 * .pi * min(hz, rate * 0.45) / rate)) }

    /// -1...1, from xorshift, the same every run.
    private mutating func random() -> Float {
        rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17
        return Float(rng >> 40) / Float(1 << 23) - 1
    }
}
