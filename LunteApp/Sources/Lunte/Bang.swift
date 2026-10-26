import AVFoundation
import FuseKit

/// The Boom out loud: `boom.wav`, straight out of the silence after the build-up, with nothing before it.
// Why: the build-up, then silence, then the bang (docs/why.md#silence-then-boom)
@MainActor
enum Bang {
    /// The cap on every sound, as a share of the Mac's volume; the slider in Settings goes up to it.
    // Why: a cartoon, not an alarm, or the sound gets switched off for good (docs/why.md#juice-inverted-u)
    static let cap: Float = 0.6
    private static var ready: (engine: AVAudioEngine, player: AVAudioPlayerNode, seconds: Double)?

    /// Gets `boom.wav` ready to go at once: loaded, its engine running and its player waiting. `pitch` plays it faster
    /// and higher for a small Boom, slower and deeper for a big one, at the same `volume`, 0...1 of `cap`.
    static func prepare(pitch: Double = 1, volume: Double = 1) {
        cancel()
        guard volume > 0, let url = Cues.url("boom"),
              let file = try? AVAudioFile(forReading: url),
              let bang = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: bang)) != nil else { return }
        let e = AVAudioEngine(), player = AVAudioPlayerNode(), speed = AVAudioUnitVarispeed()
        speed.rate = Float(pitch)
        e.attach(player)
        e.attach(speed)
        e.connect(player, to: speed, format: bang.format)
        e.connect(speed, to: e.mainMixerNode, format: bang.format)
        player.volume = cap * Float(volume) * (bang.format.channelCount == 1 ? Float(2).squareRoot() : 1) // the mixer puts mono 3 dB down a side
        player.scheduleBuffer(bang)
        guard (try? e.start()) != nil else { return }
        ready = (e, player, Double(bang.frameLength) / bang.format.sampleRate / pitch + 0.5)
    }

    /// The bang, now, if it's ready.
    static func fire() {
        guard let (e, player, seconds) = ready, e.isRunning || (try? e.start()) != nil else { return } // the Mac may have slept
        player.play()
        Task { try? await Task.sleep(for: .seconds(seconds)); if ready?.engine === e { cancel() } } // lets the speakers sleep
    }

    /// Never mind: the engine stops and the speakers sleep.
    static func cancel() {
        ready?.engine.stop()
        ready = nil
    }

    /// The bang at once, as Settings plays it when you set the volume.
    static func play(volume: Double) {
        prepare(volume: volume)
        fire()
    }
}

/// How much Lunte plays, set in Settings, at one volume. Minimal, the default, is only the Boom: its build-up, the
/// silence and the bang. Medium adds the flame: burning, crawling and dripping in the last third, and going out in
/// smoke. Maximum adds cool and a fresh fuse, and plays the flame a little louder.
// Why: the Boom is the only sound unless you ask (docs/why.md#fuse-sounds-opt-in)
enum Sounds: String, CaseIterable {
    case minimal, medium, maximum

    /// How loud the flame and the moves' own sounds play at `volume`, as a share of `Bang.cap`; the Boom plays at it.
    func flame(_ volume: Double) -> Double { self == .minimal ? 0 : self == .maximum ? 1.4 * volume : volume }
    func cues(_ volume: Double) -> Double { self == .maximum ? volume : 0 }
}

/// The flame's voice out loud, a cartoon dynamite fuse (`fuse.wav`), following the menu bar fuse frame by frame
/// (`FuseScene.voice`, `FlameSynth`): its
/// sizzle at the flame's volume, and the Boom's own race, its build-up, at the Boom's. It runs only while it sounds.
@MainActor
enum Flame {
    private static let engine: AVAudioEngine = {
        let e = AVAudioEngine(), format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let source = AVAudioSourceNode(format: format) { _, _, frames, buffers in
            let out = UnsafeMutableAudioBufferListPointer(buffers)[0].mData!.assumingMemoryBound(to: Float.self)
            flame.render(Int(frames), into: out)
            return noErr
        }
        e.attach(source)
        e.connect(source, to: e.mainMixerNode, format: format)
        return e
    }()
    private static var rest: Task<Void, Never>?

    /// Plays another fuse, or the synth with nil, and another puff (the Boom Lab's switches).
    static func use(_ recording: FlameSynth.Recording?, puff: [Float]? = nil) { Lunte.flame.use(recording, puff: puff) }

    /// Follows `voice`, its sizzle at `flame` and its race at `boom`, 0...1 of `Bang.cap`.
    static func follow(_ voice: FuseScene.Voice, flame: Double, boom: Double) {
        let gain = Bang.cap * Float(voice.race ? boom : flame)
        let quiet = gain == 0 || voice.sizzle + voice.smoke < 0.001
        guard !quiet || engine.isRunning else { return }
        Lunte.flame.set(quiet ? FuseScene.Voice(pitch: voice.pitch) : voice, gain: quiet ? nil : gain) // glides out
        if !quiet {
            rest?.cancel()
            rest = nil
            if !engine.isRunning { try? engine.start() }
        } else if rest == nil {
            rest = Task { // let the speakers sleep once it has glided out
                try? await Task.sleep(for: .seconds(0.5))
                if !Task.isCancelled { engine.stop() }
                rest = nil
            }
        }
    }
}

/// The synth the audio thread renders and the main thread steers, behind a lock.
// ponytail: a lock on the audio thread, held for a few hundred samples' worth of arithmetic; lock-free if it ever glitches
private final class FlameShared: @unchecked Sendable {
    private let lock = NSLock()
    private var synth = FlameSynth(rate: 44100), gain: Float = 0

    init() { // the shipped flame: a cartoon dynamite fuse, and a real puff as it goes out
        synth.recording = Bundle.main.url(forResource: "fuse", withExtension: "wav").flatMap { FlameSynth.Recording(calm: $0) }
        synth.puff = Bundle.main.url(forResource: "puff", withExtension: "wav").flatMap(FlameSynth.read)
    }

    func set(_ voice: FuseScene.Voice, gain: Float?) {
        lock.lock()
        synth.voice = voice
        if let gain { self.gain = gain }
        lock.unlock()
    }

    func use(_ recording: FlameSynth.Recording?, puff: [Float]?) {
        lock.lock()
        synth.recording = recording
        if let puff { synth.puff = puff }
        lock.unlock()
    }

    func render(_ count: Int, into out: UnsafeMutablePointer<Float>) {
        lock.lock()
        synth.render(count, gain: gain, into: out)
        lock.unlock()
    }
}
private let flame = FlameShared()

/// The moves' own sounds, at Maximum: `grow.wav` as cool feeds new fuse in, `fresh.wav` as a fresh fuse comes, soft and
/// well under the bang, each a little higher the shorter the fuse (`FuseScene.pitch`).
@MainActor
enum Cues {
    /// Another take of a sound, by name ("grow", "boom"), as the Boom Lab picks it; otherwise the app's own.
    static var takes: [String: URL] = [:] { didSet { reset() } }
    private struct Voice { let player = AVAudioPlayerNode(), speed = AVAudioUnitVarispeed(); let sound: AVAudioPCMBuffer }
    private static let engine = AVAudioEngine()
    private static var voices: [String: Voice] = [:]
    private static var rest: Task<Void, Never>?

    static func url(_ name: String) -> URL? { takes[name] ?? Bundle.main.url(forResource: name, withExtension: "wav") }

    /// Plays `cue` at `volume`, 0...1 of `Bang.cap`, pitched for `left` of the fuse; at 0, nothing.
    static func play(_ cue: FuseScene.Cue, left: Double, volume: Double) {
        guard volume > 0, let v = voice("\(cue)") else { return }
        v.speed.rate = Float(FuseScene.pitch(left))
        v.player.volume = Bang.cap * Float(volume)
        v.player.stop()
        v.player.scheduleBuffer(v.sound)
        v.player.play()
        rest?.cancel()
        rest = Task { // let the speakers sleep a little after the last
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { engine.stop() }
        }
    }

    /// The voice for `name`, wired into the engine and the engine running.
    private static func voice(_ name: String) -> Voice? {
        if voices[name] == nil {
            guard let url = url(name), let file = try? AVAudioFile(forReading: url),
                  let sound = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
                  (try? file.read(into: sound)) != nil else { return nil }
            let v = Voice(sound: sound)
            engine.attach(v.player)
            engine.attach(v.speed)
            engine.connect(v.player, to: v.speed, format: sound.format)
            engine.connect(v.speed, to: engine.mainMixerNode, format: sound.format)
            voices[name] = v
        }
        if !engine.isRunning { try? engine.start() }
        return engine.isRunning ? voices[name] : nil
    }

    /// Lets go of every voice, for new takes.
    private static func reset() {
        engine.stop()
        for v in voices.values { engine.detach(v.player); engine.detach(v.speed) }
        voices = [:]
    }
}
