#if DEBUG
import AppKit
import FuseKit
import SwiftUI

/// `open dist/Lunte.app --args -Lab YES`: the Boom Lab, for trying the looks and the sounds on the real menu bar and
/// screen, out loud, instead of the game. Every move of the fuse at a click, any kind of blast at any size, and any
/// take of each sound in the folder next to the app (`dist/sounds`, named `<sound>-<take>.wav`). A theme is a set of
/// these picks. Nothing is rated, logged or sent.
@MainActor
final class Lab: ObservableObject {
    @Published var kind = BlastScene.Kind.kaboom
    @Published var size = 1.0
    @Published var sounds = Sounds.maximum
    /// The flame: the recorded fuse, as shipped, from the picked takes of catch, calm and hot, or the synth; either way
    /// it goes out with the picked puff.
    @Published var recordedFlame = true { didSet { flame() } }
    @Published var volume = 1.0
    /// The take picked for each sound, a file in `folder`; none is the app's own.
    @Published private(set) var takes: [String: String] = [:]

    static let recorded = ["boom", "grow", "fresh", "catch", "calm", "hot", "puff"] // the last four: a recorded flame
    /// What's shipped, so the Lab starts out sounding like the app.
    static let shipped = ["boom": "kaboom-a.wav", "grow": "grow-a.wav", "fresh": "fresh-b.wav", "calm": "calm-c7.wav",
                          "hot": "hot-c7.wav", "puff": "puff-a.wav"]
    let folder = Bundle.main.bundleURL.deletingLastPathComponent().appending(path: "sounds")
    private let fuse: FuseView
    private var left = 1.0, prompt = 0.0
    private static var window: NSWindow?

    private init(_ fuse: FuseView) { self.fuse = fuse }

    static func open(_ fuse: FuseView) {
        let lab = Lab(fuse)
        fuse.cue = { [weak lab] in Cues.play($0, left: $1, volume: lab.map { $0.sounds.cues($0.volume) } ?? 0) }
        fuse.voice = { [weak lab] in Flame.follow($0, flame: lab.map { $0.sounds.flame($0.volume) } ?? 0, boom: lab?.volume ?? 0) }
        fuse.show(FuseLook())
        for (sound, file) in shipped where lab.files(sound).contains(file) { lab.pick(sound, file) }
        lab.flame()
        let w = NSWindow(contentViewController: NSHostingController(rootView: LabView(lab: lab)))
        w.title = "Boom Lab"
        w.styleMask = [.titled, .closable]
        w.isReleasedWhenClosed = false
        w.center()
        window = w
        NSApp.activate()
        w.makeKeyAndOrderFront(nil)
    }

    /// The takes of `sound` in `folder`: `burn-a.wav`, `burn-b.wav`… For the bang, every take of every kind's.
    func files(_ sound: String) -> [String] {
        let all = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        let kinds = BlastScene.Kind.allCases.map(\.rawValue)
        return all.filter { file in
            let name = file.split(separator: "-").first.map(String.init) ?? ""
            return file.hasSuffix(".wav") && (sound == "boom" ? kinds.contains(name) : name == sound)
        }.sorted()
    }

    func pick(_ sound: String, _ file: String) {
        takes[sound] = file.isEmpty ? nil : file
        Cues.takes[sound] = file.isEmpty ? nil : folder.appending(path: file)
        if ["catch", "calm", "hot", "puff"].contains(sound) { flame() }
    }

    fileprivate func flame() {
        let take = { (sound: String) in self.takes[sound].map { self.folder.appending(path: $0) } ?? Cues.url(sound) }
        let fuse = take("calm") ?? Cues.url("fuse")
        Flame.use(recordedFlame ? fuse.flatMap { FlameSynth.Recording(catching: take("catch"), calm: $0, hot: take("hot")) } : nil,
                  puff: take("puff").flatMap(FlameSynth.read))
    }

    // The moves, each as a prompt would bring it: a breeze while it's "rated", then what it did.
    func heat() { rated(max(0.02, left - 0.25)) }
    func cool() { rated(min(FuseScene.full, left + 0.3)) }
    func closeCall() { rated(min(left, 0.08)) }

    func fresh() {
        fuse.show(FuseLook(phase: .blown, quiet: true))
        left = 1
        Task { try? await Task.sleep(for: .seconds(0.4)); fuse.show(FuseLook()) }
    }

    /// The whole Boom: the race, 1.5 s of silence and the bang, as `kind` at `size`.
    func boom() {
        fuse.show(FuseLook(phase: .fusing, left: 0))
        Blast.run(fuse: FuseScene.raceFor + 1.5, volume: volume, scene: BlastScene(kind, size: size, seed: .random(in: 0 ... .max))) {
            [fuse] _ in fuse.show(FuseLook(phase: .blown))
        }
    }

    private func rated(_ to: Double) {
        let from = left
        prompt += 1
        left = to
        fuse.show(FuseLook(left: from, prompt: prompt, rating: true))
        Task { [prompt] in
            try? await Task.sleep(for: .seconds(0.8))
            fuse.show(FuseLook(left: to, prompt: prompt, bite: max(0, from - to)))
        }
    }
}

struct LabView: View {
    @ObservedObject var lab: Lab

    var body: some View {
        Form {
            Section("Fuse") {
                HStack {
                    Button("Heat", action: lab.heat)
                    Button("Cool", action: lab.cool)
                    Button("Close call", action: lab.closeCall)
                    Button("Fresh", action: lab.fresh)
                }
            }
            Section("Boom") {
                Picker("Kind", selection: $lab.kind) {
                    ForEach(BlastScene.Kind.allCases, id: \.self) { Text($0.rawValue.capitalized) }
                }
                Slider(value: $lab.size, in: 0.8...1.25) { Text("Size") }
                Button("Boom", action: lab.boom)
            }
            Section("Sound") {
                Picker("Flame", selection: $lab.recordedFlame) {
                    Text("Synth").tag(false)
                    Text("Recorded").tag(true)
                }
                .pickerStyle(.segmented)
                Picker("Sound effects", selection: $lab.sounds) {
                    ForEach(Sounds.allCases, id: \.self) { Text($0.rawValue.capitalized) }
                }
                .pickerStyle(.segmented)
                Slider(value: $lab.volume, in: 0...1) { Text("Volume") }
            }
            Section {
                ForEach(Lab.recorded, id: \.self) { sound in
                    Picker(sound.capitalized, selection: Binding(get: { lab.takes[sound] ?? "" }, set: { lab.pick(sound, $0) })) {
                        Text("The app's own").tag("")
                        ForEach(lab.files(sound), id: \.self) { Text($0).tag($0) }
                    }
                }
            } header: {
                Text("Takes")
            } footer: {
                Text("From \(lab.folder.path)").foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize()
    }
}
#endif
