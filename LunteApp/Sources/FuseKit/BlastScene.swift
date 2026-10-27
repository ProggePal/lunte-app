import AppKit
import Metal
import QuartzCore

/// The Boom on screen, drawn like `FuseScene` as a pure function of time, so any frame can be looked at without running
/// the app (`scripts/render-fuse.sh blast`). It's Metal: a fireball of turbulent noise that cools from white through
/// orange to red and rolls into faint smoke, the light it throws on the dark screen, a shockwave, and sparks that fly
/// with drag and gravity, streaked by their own motion. All of it starts in the stillness and eases back up to speed.
///
/// Each Boom blows its own way: a kaboom at a size picked from its seed, its sparks and its fire's turbulence from the
/// seed too, never from its heat, so the bang stays fresh without paying more for more anger. A kind is only a recipe,
/// numbers: the others wait for later, as skins, and the renders still draw them.
// Why: variety, not volume, against habituation (docs/why.md#every-boom-its-own)
public struct BlastScene {
    public enum Kind: String, CaseIterable {
        case burst   // the classic: a fireball, a spray of sparks, embers and smoke
        case crackle // a sharp little pop, and sparks that crackle where they burn out
        case willow  // gold glitter that droops and rains down from the menu bar
        case ring    // a perfect ring of sparks, and a strong shockwave
        case kaboom  // the big one: a fireball of three, heavy sparks and more smoke
    }

    public let kind: Kind
    /// How big, as a share of the kind's own size.
    public let size: Double
    public let seed: UInt32

    /// The Boom for `seed`, such as its id: a kaboom, 0.8 to 1.25 of its size, from the seed alone.
    public init(seed: UInt64) {
        self.init(.kaboom, size: 0.8 + 0.45 * Double(Self.mix(Self.mix(seed)) % 1024) / 1023, seed: seed)
    }

    public init(_ kind: Kind, size: Double = 1, seed: UInt64 = 1) {
        self.kind = kind
        self.size = size
        self.seed = UInt32(truncatingIfNeeded: Self.mix(seed ^ 0x5eed) % (1 << 20)) // exact as a float in the shader
    }

    /// The blast's own clock, `since` seconds after the bang: it starts from a near stop and eases back up to full speed
    /// over `FuseScene.speedUp`, the integral of a speed from 0.05 to 1. The flash keeps real time.
    // Why: hitstop, a beat of stillness on impact (docs/why.md#boom-in-the-stillness)
    public static func time(_ since: Double) -> Double {
        let u = min(1, max(0, since / FuseScene.speedUp))
        return FuseScene.speedUp * (0.05 * u + 0.95 * u * u * u / 3) + max(0, since - FuseScene.speedUp)
    }

    /// How fast the blast's clock runs at `since`, from 0.05 to 1: the motion blur is a real moment's worth of its path,
    /// so in the stillness the sparks are crisp, as on slow-motion film.
    static func pace(_ since: Double) -> Double {
        let u = min(1, max(0, since / FuseScene.speedUp))
        return 0.05 + 0.95 * u * u
    }

    /// The whole screen's flash at `since`, in real time: up in 30 ms, and gone in a few tenths.
    public func flash(_ since: Double) -> Double {
        guard since >= 0 else { return 0 }
        return recipe.flash * (since < 0.03 ? since / 0.03 : exp(-(since - 0.03) / 0.11))
    }

    /// When it's all gone, by the blast's own clock: the last spark out and the smoke faded.
    public var over: Double {
        let sparks = recipe.sparks.map { $0.delay + $0.life * (1 + $0.lifeSpread) + $0.trail + $0.childLife * 1.4 }
        return max(sparks.max() ?? 0, 2.2 * recipe.smoke + 1.2)
    }

    /// How fast the bang plays, so a big one sounds deeper and a small one snappier, 0.89 to 1.12. Never louder.
    public var pitch: Double { (1 / size).squareRoot() }

    // MARK: Recipes

    /// What a kind is made of, at size 1, in points and seconds. Distances grow with the size; times don't.
    struct Recipe {
        var fireball = 70.0 // the fireball's radius at its widest
        var fireLife = 0.45 // how long it burns hot
        var lobes = 0.0     // more fireballs, bursting out of the first
        var smoke = 0.8
        var ring = 1.0      // the shockwave's strength
        var reach = 380.0   // how far its light reaches on the dark screen
        var gold = 0.0      // the fire's colour: -1 crimson, 0 orange, 1 gold
        var flash = 0.42    // the whole screen's flash at its peak
        var sparks: [Sparks] = []
    }

    /// A family of sparks, all from where it blew.
    struct Sparks {
        var count = 200.0
        var speed = 400.0, spread = 0.6 // points a second, and how far either side of it, as a share
        var drag = 2.2, gravity = 500.0 // per second, and points a second squared, down
        var life = 1.2, lifeSpread = 0.4
        var width = 1.0
        var shutter = 0.035             // the motion blur, as seconds of its path
        var trail = 0.0, segments = 1.0 // a long trail behind it, in seconds of its path and pieces, so it can curve
        var ring = 0.0                  // 1: all at one speed, evenly spread, so they make a ring
        var twinkle = 0.0
        var hot = 0.95                  // how hot it starts: 1 white, 0.6 orange
        var delay = 0.03                // births spread over this long
        var gold = 0.0
        var children = 0.0, childSpeed = 0.0, childLife = 0.0 // where it burns out, a crackle: a pop and tiny sparks

        func floats(family: Int) -> [Float] {
            [count, speed, spread, drag, gravity, life, lifeSpread, width, shutter, trail, segments, ring, twinkle, hot,
             delay, Double(family), gold, children, childSpeed, childLife].map { Float($0) }
        }
    }

    var recipe: Recipe { Self.recipes[kind]! }

    static let recipes: [Kind: Recipe] = [
        .burst: Recipe(fireball: 85, fireLife: 0.55, sparks: [
            Sparks(count: 220, speed: 420, life: 1.2, lifeSpread: 0.5),
            Sparks(count: 50, speed: 160, spread: 0.7, drag: 1.4, gravity: 70, life: 2.4, width: 1.3, shutter: 0.02,
                   twinkle: 0.35, hot: 0.7, delay: 0.15), // embers
        ]),
        .crackle: Recipe(fireball: 38, fireLife: 0.3, smoke: 0.45, ring: 0.6, reach: 260, flash: 0.32, sparks: [
            Sparks(count: 110, speed: 360, spread: 0.45, drag: 2.6, gravity: 380, life: 0.65, lifeSpread: 0.6, width: 0.9,
                   children: 9, childSpeed: 260, childLife: 0.22),
        ]),
        .willow: Recipe(fireball: 48, fireLife: 0.35, smoke: 0.4, ring: 0.5, reach: 320, gold: 1, flash: 0.32, sparks: [
            Sparks(count: 170, speed: 300, spread: 0.3, drag: 1.5, gravity: 190, life: 2.8, lifeSpread: 0.25, width: 0.9,
                   trail: 0.5, segments: 5, twinkle: 0.7, hot: 0.75, gold: 1),
        ]),
        .ring: Recipe(fireball: 34, fireLife: 0.3, smoke: 0.5, ring: 1.3, reach: 280, gold: -1, flash: 0.32, sparks: [
            Sparks(count: 90, speed: 380, drag: 2.3, gravity: 150, life: 1.25, lifeSpread: 0.08, width: 1.2, ring: 1, hot: 1,
                   delay: 0),
            Sparks(count: 60, speed: 230, drag: 2.3, gravity: 150, life: 1.1, lifeSpread: 0.08, width: 1, ring: 1, hot: 0.85,
                   delay: 0.02, gold: -1),
        ]),
        .kaboom: Recipe(fireball: 105, fireLife: 0.6, lobes: 3, smoke: 1.1, ring: 1.3, reach: 500, flash: 0.48, sparks: [
            Sparks(count: 300, speed: 520, drag: 2, gravity: 600, life: 1.4, lifeSpread: 0.5, width: 1.1),
            Sparks(count: 90, speed: 190, spread: 0.7, drag: 1.3, gravity: 80, life: 3.6, width: 1.4, shutter: 0.02,
                   twinkle: 0.35, hot: 0.7, delay: 0.25), // embers
            // Why: the aftermath lingers, so the Boom keeps on after the bang without getting louder (docs/why.md#boom-in-the-stillness)
            Sparks(count: 45, speed: 110, spread: 0.9, drag: 0.9, gravity: 28, life: 5, lifeSpread: 0.35, width: 1.2, shutter: 0.02,
                   twinkle: 0.6, hot: 0.62, delay: 0.5), // cinders, drifting down long after, glowing out
        ]),
    ]

    /// The scene's numbers for the shaders, in the order `Scene` in `BlastRenderer.source` has them.
    func uniforms(since: Double, at: CGPoint, in size: CGSize) -> [Float] {
        let r = recipe
        return [size.width, size.height, at.x, at.y, Self.time(since), flash(since), Double(seed), self.size,
                r.fireball, r.fireLife, r.lobes, r.smoke, r.ring, r.reach, r.gold, Self.pace(since)].map { Float($0) }
    }

    /// splitmix64: neighbouring ids, a millisecond apart, pick unrelated booms.
    static func mix(_ x: UInt64) -> UInt64 {
        var z = x &+ 0x9e3779b97f4a7c15
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
    }
}

// MARK: - Drawing

/// Draws a `BlastScene` with Metal, live into a layer or offline into an image. The shaders are compiled from source
/// when it's made, which takes a few tenths of a second, so make it ahead of the bang, off the main thread.
public final class BlastRenderer {
    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let fire, sparks, show: MTLRenderPipelineState
    private var hdr: MTLTexture?

    public init?() {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
              let library = try? device.makeLibrary(source: Self.source, options: nil) else { return nil }
        func pipeline(_ vertex: String, _ fragment: String, _ format: MTLPixelFormat, additive: Bool = false) -> MTLRenderPipelineState? {
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = library.makeFunction(name: vertex)
            d.fragmentFunction = library.makeFunction(name: fragment)
            let c = d.colorAttachments[0]!
            c.pixelFormat = format
            if additive { // light adds up; the smoke's cover stays as it is
                c.isBlendingEnabled = true
                c.sourceRGBBlendFactor = .one
                c.destinationRGBBlendFactor = .one
                c.sourceAlphaBlendFactor = .zero
                c.destinationAlphaBlendFactor = .one
            }
            return try? device.makeRenderPipelineState(descriptor: d)
        }
        guard let fire = pipeline("whole", "fire", .rgba16Float),
              let sparks = pipeline("spark", "streak", .rgba16Float, additive: true),
              let show = pipeline("whole", "show", .bgra8Unorm) else { return nil }
        (self.device, self.queue, self.fire, self.sparks, self.show) = (device, queue, fire, sparks, show)
    }

    /// Draws `scene` at `since` seconds after the bang into `target`, which covers `size` points at `scale` pixels a
    /// point, blowing from `at` (points, y up). Premultiplied, clear where there's nothing.
    public func draw(_ scene: BlastScene, since: Double, at: CGPoint, size: CGSize, to target: MTLTexture) -> MTLCommandBuffer? {
        if hdr?.width != target.width || hdr?.height != target.height {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: target.width, height: target.height, mipmapped: false)
            d.usage = [.renderTarget, .shaderRead]
            d.storageMode = .private
            hdr = device.makeTexture(descriptor: d)
        }
        guard let hdr, let buffer = queue.makeCommandBuffer() else { return nil }
        var u = scene.uniforms(since: since, at: at, in: size)
        let pass = { (texture: MTLTexture) -> MTLRenderPassDescriptor in
            let p = MTLRenderPassDescriptor()
            p.colorAttachments[0].texture = texture
            p.colorAttachments[0].loadAction = .clear
            p.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            p.colorAttachments[0].storeAction = .store
            return p
        }
        // The fire, the smoke and the light, then the sparks on top, in light that can go past white…
        guard let e = buffer.makeRenderCommandEncoder(descriptor: pass(hdr)) else { return nil }
        e.setRenderPipelineState(fire)
        e.setVertexBytes(&u, length: u.count * 4, index: 0)
        e.setFragmentBytes(&u, length: u.count * 4, index: 0)
        e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        e.setRenderPipelineState(sparks)
        e.setVertexBytes(&u, length: u.count * 4, index: 0)
        for (family, s) in scene.recipe.sparks.enumerated() {
            var f = s.floats(family: family)
            e.setVertexBytes(&f, length: f.count * 4, index: 1)
            for children: Float in s.children > 0 ? [0, 1] : [0] {
                var c = children
                e.setVertexBytes(&c, length: 4, index: 2)
                let n = Int(s.count) * (children > 0 ? Int(s.children) : Int(s.segments))
                e.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: n)
            }
        }
        e.endEncoding()
        // …then toned down to the screen, with the flash over it all.
        guard let s = buffer.makeRenderCommandEncoder(descriptor: pass(target)) else { return nil }
        s.setRenderPipelineState(show)
        s.setVertexBytes(&u, length: u.count * 4, index: 0)
        s.setFragmentBytes(&u, length: u.count * 4, index: 0)
        s.setFragmentTexture(hdr, index: 0)
        s.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        s.endEncoding()
        return buffer
    }

    /// Lets go of the screen-sized buffer between Booms, a few tens of megabytes.
    public func rest() { hdr = nil }

    /// One frame as an image, `size` points at `scale`, for the renders.
    public func image(_ scene: BlastScene, since: Double, at: CGPoint, size: CGSize, scale: Double = 1) -> CGImage? {
        let w = Int(size.width * scale), h = Int(size.height * scale)
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
        d.usage = [.renderTarget]
        d.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: d),
              let buffer = draw(scene, since: since, at: at, size: size, to: texture) else { return nil }
        buffer.commit()
        buffer.waitUntilCompleted()
        var px = [UInt8](repeating: 0, count: w * h * 4)
        texture.getBytes(&px, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        return CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                         space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info)?.makeImage()
    }

    static let source = #"""
    #include <metal_stdlib>
    using namespace metal;

    // BlastScene.uniforms: floats only, so they line up with Swift's [Float].
    struct Scene {
        float w, h, x, y;     // the target and where it blew, in points, y up
        float t, flash;       // the blast's own time, s, and the screen's flash, 0...1
        float seed, size;
        float fireball, fireLife, lobes, smoke, ring, reach, gold, pace;
    };

    // BlastScene.Sparks.floats.
    struct Sparks {
        float count, speed, spread, drag, gravity, life, lifeSpread, width;
        float shutter, trail, segments, ring, twinkle, hot, delay, family;
        float gold, children, childSpeed, childLife;
    };

    static float hash(uint a, uint b, uint c) {
        uint h = a * 747796405u + b * 2891336453u + c * 1181783497u;
        h ^= h >> 16; h *= 0x7feb352du; h ^= h >> 15; h *= 0x846ca68bu; h ^= h >> 16;
        return float(h) / 4294967295.0;
    }

    static float noise(float3 p) {
        float3 i = floor(p), f = fract(p), u = f * f * f * (f * (f * 6 - 15) + 10);
        uint3 q = as_type<uint3>(int3(i));
        float n[8];
        for (uint k = 0; k < 8; k++) n[k] = hash(q.x + (k & 1), q.y + ((k >> 1) & 1), q.z + (k >> 2));
        return mix(mix(mix(n[0], n[1], u.x), mix(n[2], n[3], u.x), u.y), mix(mix(n[4], n[5], u.x), mix(n[6], n[7], u.x), u.y), u.z);
    }

    static float fbm(float3 p) {
        float sum = 0, amp = 0.5;
        for (int k = 0; k < 5; k++) {
            sum += amp * noise(p);
            p = float3(p.x * 1.6 - p.y * 1.2, p.x * 1.2 + p.y * 1.6, p.z * 1.7) + 7.3; // turn each octave, so no grid shows
            amp *= 0.5;
        }
        return sum / 0.97;
    }

    // Fire's colour at temperature T, 0...1, in linear light: white-hot, yellow, orange, red, out. Gold burns
    // yellower, crimson redder.
    static float3 fire(float T, float gold) {
        T = saturate(T);
        return pow(float3(T), float3(1, 2.5 - 0.9 * gold, 6 - 2 * gold));
    }

    struct Whole { float4 pos [[position]]; float2 pt; };

    vertex Whole whole(uint v [[vertex_id]], constant Scene& s [[buffer(0)]]) {
        float2 uv = float2((v << 1) & 2, v & 2);
        Whole o;
        o.pos = float4(uv * 2 - 1, 0, 1);
        o.pt = uv * float2(s.w, s.h);
        return o;
    }

    fragment float4 fire(Whole in [[stage_in]], constant Scene& s [[buffer(0)]]) {
        float2 p = (in.pt - float2(s.x, s.y)) / s.size; // from where it blew, at size 1
        float t = s.t, r = length(p), k = fmod(s.seed, 97.0);
        uint seed = uint(s.seed);
        float3 col = 0;
        float cover = 0;
        if (t <= 0) return float4(0);

        // The light it throws on the dark screen, flickering as the fire dies.
        float flicker = 0.75 + 0.25 * noise(float3(t * 16, k, 3));
        float light = (1 - exp(-t * 60)) * exp(-t / (0.2 + s.fireLife)) * flicker;
        col += fire(0.75, s.gold) * light * 0.8 / (1 + pow(r / (0.3 * s.reach), 2));

        // The shockwave: a crisp edge racing out, a soft band behind it.
        if (s.ring > 0) {
            float wob = 1 + 0.04 * (noise(float3(normalize(p + 1e-4) * 2.5, k + t)) - 0.5);
            float rs = 2.6 * s.fireball * (1 - exp(-t * 5)) * wob, width = 2 + 18 * t;
            float edge = exp(-pow((r - rs) / 2.5, 2)), band = r < rs ? exp(-pow((rs - r) / width, 2)) : edge;
            col += float3(1, 0.8, 0.62) * s.ring * exp(-t * 4.5) * (0.45 * edge + 0.35 * band);
        }

        // The fireball, and more bursting out of it: turbulent, cooling, rising, and rolling into smoke.
        for (int i = 0; i <= int(s.lobes); i++) {
            float tt = t - (i == 0 ? 0 : 0.04 + 0.05 * i);
            if (tt <= 0) continue;
            float ang = -1.5708 + (hash(seed, i, 7) - 0.5) * 2.6; // mostly down, away from the menu bar
            float2 c = i == 0 ? float2(0) : float2(cos(ang), sin(ang)) * s.fireball * (0.55 + 0.35 * hash(seed, i, 8));
            float R = s.fireball * (i == 0 ? 1 : 0.6) * (0.3 + 0.7 * (1 - exp(-tt * 8))) * (1 + 0.3 * tt); // in at once, then out
            c.y += 26 * tt * tt; // hot gas rises
            float2 q = (p - c) / max(R, 1.0);
            if (dot(q, q) > 4) continue;
            float3 nq = float3(q * 1.8, tt * 0.8 + k + i * 3.1);
            float2 w = float2(fbm(nq), fbm(nq + float3(5.2, 1.3, 2.8))) - 0.5;
            float d = length(q + w * 0.75);
            float detail = fbm(float3(q * 3.4 + w * 2.2, tt * 1.5 + k + 11));
            float heat = exp(-tt / s.fireLife);
            float dens = smoothstep(1.05, 0.15, d) * (0.55 + 0.8 * detail);
            float T = dens * (0.25 + 0.95 * heat) * (1.15 - 0.35 * d);
            col += fire(T, s.gold) * 3 * smoothstep(0.0, 0.08, T);
            col += float3(4) * exp(-tt / 0.05) * exp(-dot(q, q) * 4); // the white-hot instant
            // Smoke, as the fire dies: dark, lit from inside while it's hot, faint, and fading.
            float sd = smoothstep(1.25, 0.25, length(q * 0.85 + w * 0.9)) * smoothstep(0.35, 0.75, detail);
            float sa = s.smoke * 0.42 * sd * smoothstep(0.05, 0.4, tt) * exp(-tt / (1.6 * s.smoke + 0.4));
            float3 sc = mix(float3(0.045, 0.04, 0.036), fire(0.6, s.gold) * 0.5, heat * 0.7);
            col = col * (1 - sa) + sc * sa;
            cover = cover + sa * (1 - cover);
        }
        return float4(col, cover);
    }

    struct Streak { float4 pos [[position]]; float2 pt; float2 a [[flat]]; float2 b [[flat]]; float3 col [[flat]]; float w [[flat]]; };

    // Where a spark is `age` s after it flew at `v0`, with drag `k` and gravity `g`: no stepping, so any moment is exact.
    static float2 path(float2 v0, float k, float g, float age) {
        float2 vt = float2(0, -g / k);
        return vt * age + (v0 - vt) * (1 - exp(-k * age)) / k;
    }

    vertex Streak spark(uint v [[vertex_id]], uint inst [[instance_id]], constant Scene& s [[buffer(0)]],
                        constant Sparks& f [[buffer(1)]], constant float& crackle [[buffer(2)]]) {
        Streak o;
        o.pos = float4(-2, -2, 0, 1); // off screen: nothing to draw
        uint seed = uint(s.seed), fam = uint(f.family) * 65536;
        uint segs = crackle > 0 ? 1 : max(1u, uint(f.segments));
        uint seg = inst % segs, i = inst / segs, child = 0;
        if (crackle > 0) { child = i % uint(f.children); i /= uint(f.children); }
        float h1 = hash(seed, fam + i, 1), h2 = hash(seed, fam + i, 2), h3 = hash(seed, fam + i, 3);
        float h4 = hash(seed, fam + i, 4), h5 = hash(seed, fam + i, 5);
        float ang = f.ring > 0 ? (i + 0.3 * h1) / f.count * 6.2832 + hash(seed, fam, 9) * 6.2832 : h1 * 6.2832;
        float speed = f.speed * s.size * (f.ring > 0 ? 1 + 0.04 * (h2 - 0.5) : 1 + f.spread * (2 * h2 - 1));
        float born = f.delay * h3, life = f.life * (1 + f.lifeSpread * (2 * h4 - 1));
        float k = f.drag * (0.8 + 0.4 * h5), g = f.gravity * s.size;
        float2 v0 = float2(cos(ang), sin(ang)) * speed, from = 0;
        float age = s.t - born, hot = f.hot, width = f.width, gold = f.gold, trail = f.trail;
        if (crackle > 0) {
            // It crackles where it burnt out: a pop of white, then a few tiny sparks.
            from = path(v0, k, g, life);
            age -= life;
            float c1 = hash(seed, fam + i, 20 + child), c2 = hash(seed, fam + i, 40 + child);
            if (child == 0) { v0 = 0; life = 0.07; width = 5; }
            else { v0 = float2(cos(c1 * 6.2832), sin(c1 * 6.2832)) * f.childSpeed * s.size * (0.4 + 0.6 * c2); life = f.childLife * (0.6 + 0.8 * c2); width = 0.7; }
            k = 6; g = 250 * s.size; hot = 1; trail = 0;
        }
        if (age <= 0 || age >= life) return o;
        float a0 = trail > 0 ? age - trail * seg / segs : age;
        float a1 = trail > 0 ? age - trail * (seg + 1) / segs : age - f.shutter * s.pace;
        a1 = max(a1, 0.0);
        if (a0 <= a1 && seg > 0) return o;
        float2 A = from + path(v0, k, g, a0) * 1, B = from + path(v0, k, g, a1);
        float u = age / life;
        float T = hot * pow(1 - u, 0.55);
        float bright = smoothstep(1.0, 0.65, u) * pow(1 - float(seg) / segs, 1.6);
        if (f.twinkle > 0) bright *= mix(1.0, hash(seed, fam + i * 131 + uint(age * 28), 6) > 0.45 ? 1.5 : 0.12, f.twinkle);
        float len = length(A - B);
        bright *= min(1.0, sqrt(3 * width / max(len, 0.01))); // a long streak spreads its light
        o.col = fire(T, gold) * 3.2 * bright;
        o.w = width;
        o.a = A; o.b = B;
        float R = width * 6 + 1; // as far as its glow reaches: `streak` fades it out by here
        float2 d = len > 1e-3 ? (A - B) / len : float2(1, 0), n = float2(-d.y, d.x);
        float2 corner = ((v & 1) ? A + d * R : B - d * R) + n * R * ((v & 2) ? 1 : -1);
        o.pt = corner;
        float2 at = (corner + float2(s.x, s.y)) / float2(s.w, s.h);
        o.pos = float4(at * 2 - 1, 0, 1);
        return o;
    }

    fragment float4 streak(Streak in [[stage_in]]) {
        float2 ab = in.a - in.b;
        float h = saturate(dot(in.pt - in.b, ab) / max(dot(ab, ab), 1e-4));
        float d = length(in.pt - in.b - ab * h);
        float edge = saturate(1 - d / (in.w * 6 + 1)); // nothing at the quad's edge, so no glow ends in a square
        float core = exp(-(d * d) / (in.w * in.w)), halo = 0.28 * exp(-d / (in.w * 2.2)) * edge * edge;
        return float4(in.col * (core + halo), 0);
    }

    static float3 srgb(float3 c) { return select(1.055 * pow(c, 1 / 2.4) - 0.055, 12.92 * c, c <= 0.0031308); }

    fragment float4 show(Whole in [[stage_in]], constant Scene& s [[buffer(0)]], texture2d<float> hdr [[texture(0)]]) {
        float4 c = hdr.read(uint2(in.pos.xy));
        float3 m = 1 - exp(-c.rgb); // soft past white, like film
        float a = saturate(max(c.a, max(m.r, max(m.g, m.b))));
        float3 out = a > 0 ? srgb(saturate(m / a)) * a : float3(0);
        float f = s.flash;
        return float4(float3(1, 0.93, 0.82) * f + out * (1 - f), f + a * (1 - f));
    }
    """#
}

/// The blast live over a screen: a Metal layer the display link redraws from the bang until it's over.
public final class BlastView: NSView {
    private let renderer: BlastRenderer
    private let scene: BlastScene
    private let at: CGPoint
    private var bangAt: Double?
    private var link: CADisplayLink?
    /// Called once it's over.
    public var done: () -> Void = {}

    /// Blowing from `at`, in the view's points, y up.
    public init(frame: NSRect, renderer: BlastRenderer, scene: BlastScene, at: CGPoint) {
        self.renderer = renderer
        self.scene = scene
        self.at = at
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    public override func makeBackingLayer() -> CALayer {
        let layer = CAMetalLayer()
        layer.device = renderer.device
        layer.pixelFormat = .bgra8Unorm
        layer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        layer.isOpaque = false
        layer.framebufferOnly = true
        return layer
    }

    public override func hitTest(_ point: NSPoint) -> NSView? { nil }

    public func bang() {
        bangAt = CACurrentMediaTime()
        link = displayLink(target: self, selector: #selector(tick))
        link?.add(to: .main, forMode: .common)
    }

    @objc private func tick() {
        guard let bangAt, let layer = layer as? CAMetalLayer else { return }
        let since = CACurrentMediaTime() - bangAt
        guard BlastScene.time(since) < scene.over else {
            link?.invalidate()
            link = nil
            renderer.rest()
            return done()
        }
        let scale = window?.backingScaleFactor ?? 2
        layer.contentsScale = scale
        layer.drawableSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        guard let drawable = layer.nextDrawable(),
              let buffer = renderer.draw(scene, since: since, at: at, size: bounds.size, to: drawable.texture) else { return }
        buffer.present(drawable)
        buffer.commit()
    }
}
