import AppKit
import Metal
import SceneKit
import simd

final class RugScene: SCNView {
    static let size = SIMD2<Float>(620, 390)

    private var sim: ClothSim!
    private let cameraNode = SCNNode()
    private let lightNode = SCNNode()
    private var frontNode = SCNNode()
    private var backNode = SCNNode()
    private var vertexBuffer: MTLBuffer?
    private var normalBuffer: MTLBuffer?
    private let depth: Float = 2400

    private var link: CADisplayLink?
    private var quietFrames = 0
    private var smoothedTarget = SIMD3<Float>.zero
    private var rawTarget = SIMD3<Float>.zero
    private var grabbing = false
    private var hovered: Int?
    private var script: Script?
    private var settleUntil: CFTimeInterval = 0

    var onRest: ((SIMD2<Float>) -> Void)?
    var onOutline: ((CGPath) -> Void)?

    private struct Script {
        let particle: Int
        let from: SIMD3<Float>
        let to: SIMD3<Float>
        let lift: Float
        let start: CFTimeInterval
        let duration: CFTimeInterval
    }

    init(frame: CGRect, center: SIMD2<Float>) {
        super.init(frame: frame, options: [SCNView.Option.preferredRenderingAPI.rawValue: SCNRenderingAPI.metal.rawValue])
        backgroundColor = .clear
        layer?.isOpaque = false
        antialiasingMode = .multisampling4X
        allowsCameraControl = false
        isPlaying = false
        rendersContinuously = false
        sim = ClothSim(size: Self.size, center: center)
        buildScene()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func buildScene() {
        let scene = SCNScene()
        scene.background.contents = NSColor.clear
        self.scene = scene

        let camera = SCNCamera()
        camera.zNear = 1
        camera.zFar = Double(depth) + 1000
        camera.projectionDirection = .vertical
        cameraNode.camera = camera
        scene.rootNode.addChildNode(cameraNode)

        let light = SCNLight()
        light.type = .directional
        light.intensity = 760
        lightNode.light = light
        scene.rootNode.addChildNode(lightNode)

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 420
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        buildCloth(in: scene)
        layoutCamera()
        upload()
    }

    private func buildCloth(in scene: SCNScene) {
        guard let device else { return }
        let count = sim.position.count
        vertexBuffer = device.makeBuffer(length: count * MemoryLayout<SIMD3<Float>>.stride, options: .storageModeShared)
        normalBuffer = device.makeBuffer(length: count * MemoryLayout<SIMD3<Float>>.stride, options: .storageModeShared)
        guard let vertexBuffer, let normalBuffer else { return }

        let stride = MemoryLayout<SIMD3<Float>>.stride
        let vertices = SCNGeometrySource(buffer: vertexBuffer, vertexFormat: .float3, semantic: .vertex, vertexCount: count, dataOffset: 0, dataStride: stride)
        let normals = SCNGeometrySource(buffer: normalBuffer, vertexFormat: .float3, semantic: .normal, vertexCount: count, dataOffset: 0, dataStride: stride)
        var uv: [CGPoint] = []
        for j in 0..<sim.rows {
            for i in 0..<sim.cols {
                uv.append(CGPoint(x: Double(i) / Double(sim.cols - 1), y: 1 - Double(j) / Double(sim.rows - 1)))
            }
        }
        let coordinates = SCNGeometrySource(textureCoordinates: uv)

        var indices: [UInt32] = []
        for j in 0..<(sim.rows - 1) {
            for i in 0..<(sim.cols - 1) {
                let a = UInt32(sim.index(i, j))
                let b = UInt32(sim.index(i + 1, j))
                let c = UInt32(sim.index(i + 1, j + 1))
                let d = UInt32(sim.index(i, j + 1))
                indices += [a, b, c, a, c, d]
            }
        }
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)

        let art = RugArt.make(size: CGSize(width: CGFloat(Self.size.x), height: CGFloat(Self.size.y)), scale: 2)
        let cutout: [SCNShaderModifierEntryPoint: String] = [.fragment: "if (_output.color.a < 0.5) { discard_fragment(); }"]

        let front = SCNMaterial()
        front.diffuse.contents = art?.front
        front.lightingModel = .lambert
        front.cullMode = .back
        front.blendMode = .replace
        front.shaderModifiers = cutout

        let back = SCNMaterial()
        back.diffuse.contents = art?.back
        back.lightingModel = .lambert
        back.cullMode = .front
        back.blendMode = .replace
        var flipped = cutout
        flipped[.geometry] = "_geometry.normal = -_geometry.normal;"
        back.shaderModifiers = flipped

        let frontGeometry = SCNGeometry(sources: [vertices, normals, coordinates], elements: [element])
        frontGeometry.firstMaterial = front
        let backGeometry = SCNGeometry(sources: [vertices, normals, coordinates], elements: [element])
        backGeometry.firstMaterial = back

        frontNode = SCNNode(geometry: frontGeometry)
        backNode = SCNNode(geometry: backGeometry)
        scene.rootNode.addChildNode(frontNode)
        scene.rootNode.addChildNode(backNode)
    }

    override func layout() {
        super.layout()
        layoutCamera()
    }

    private func layoutCamera() {
        let width = Float(bounds.width)
        let height = Float(bounds.height)
        guard width > 0, height > 0 else { return }
        cameraNode.position = SCNVector3(width / 2, height / 2, depth)
        cameraNode.camera?.fieldOfView = CGFloat(2 * atan(height / 2 / depth) * 180 / .pi)

        lightNode.position = SCNVector3(width / 2 - 500, height / 2 + 700, 3000)
        lightNode.look(at: SCNVector3(width / 2, height / 2, 0))
    }

    private var eye: SIMD2<Float> { SIMD2(Float(bounds.width) / 2, Float(bounds.height) / 2) }

    private func project(_ p: SIMD3<Float>) -> SIMD2<Float> {
        eye + (SIMD2(p.x, p.y) - eye) * (depth / (depth - p.z))
    }

    private func unproject(_ point: CGPoint, height: Float) -> SIMD3<Float> {
        let s = SIMD2(Float(point.x), Float(point.y))
        let xy = eye + (s - eye) * ((depth - height) / depth)
        return SIMD3(xy.x, xy.y, height)
    }

    func refreshOutline() {
        onOutline?(outline())
    }

    private func outline() -> CGPath {
        var loop: [Int] = []
        for i in 0..<sim.cols { loop.append(sim.index(i, 0)) }
        for j in 1..<sim.rows { loop.append(sim.index(sim.cols - 1, j)) }
        for i in stride(from: sim.cols - 2, through: 0, by: -1) { loop.append(sim.index(i, sim.rows - 1)) }
        for j in stride(from: sim.rows - 2, through: 1, by: -1) { loop.append(sim.index(0, j)) }

        let path = CGMutablePath()
        for (n, index) in loop.enumerated() {
            let p = sim.position[index]
            let point = CGPoint(x: CGFloat(p.x + p.z * 0.45 + 2), y: CGFloat(p.y - p.z * 0.6 - 4))
            n == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }

    private func upload() {
        onOutline?(outline())
        guard let vertexBuffer, let normalBuffer else { return }
        sim.position.withUnsafeBytes { bytes in
            vertexBuffer.contents().copyMemory(from: bytes.baseAddress!, byteCount: bytes.count)
        }
        let normals = sim.normals()
        normals.withUnsafeBytes { bytes in
            normalBuffer.contents().copyMemory(from: bytes.baseAddress!, byteCount: bytes.count)
        }
    }

    private func wake() {
        quietFrames = 0
        rendersContinuously = true
        guard link == nil else { return }
        let link = displayLink(target: self, selector: #selector(frame(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    private func sleep() {
        link?.invalidate()
        link = nil
        rendersContinuously = false
        needsDisplay = true
        if sim.isFlat { onRest?(sim.flatOffset()) }
    }

    @objc private func frame(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        let elapsed = min(max(link.targetTimestamp - link.timestamp, 1.0 / 240), 1.0 / 30)
        if let script {
            let t = Float(min((now - script.start) / script.duration, 1))
            let eased = t * t * (3 - 2 * t)
            var point = script.from + (script.to - script.from) * eased
            point.z = script.from.z + (script.to.z - script.from.z) * eased + script.lift * sin(eased * .pi)
            sim.pinned = script.particle
            rawTarget = point
            smoothedTarget = point
            if t >= 1 {
                self.script = nil
                sim.pinned = nil
            }
        } else if grabbing || hovered != nil {
            let follow = Float(1 - exp(-elapsed * 22))
            smoothedTarget += (rawTarget - smoothedTarget) * follow
        }
        sim.pinTarget = smoothedTarget

        if now < settleUntil {
            sim.settleStrength = 0.05
        } else {
            sim.settleStrength = 0
            sim.settleTarget = nil
        }

        var motion: Float = 0
        let substeps = max(1, Int((elapsed * 240).rounded()))
        for _ in 0..<substeps {
            motion = max(motion, sim.step(1.0 / 240))
        }
        upload()

        let busy = grabbing || hovered != nil || script != nil || now < settleUntil
        quietFrames = !busy && motion < 0.05 ? quietFrames + 1 : 0
        if quietFrames > 45 { sleep() }
    }

    private func visibleTriangles(contains point: SIMD2<Float>) -> Bool {
        var projected = [SIMD2<Float>](repeating: .zero, count: sim.position.count)
        var minimum = SIMD2<Float>(repeating: .greatestFiniteMagnitude)
        var maximum = SIMD2<Float>(repeating: -.greatestFiniteMagnitude)
        for i in sim.position.indices {
            projected[i] = project(sim.position[i])
            minimum = simd_min(minimum, projected[i])
            maximum = simd_max(maximum, projected[i])
        }
        guard point.x >= minimum.x, point.y >= minimum.y, point.x <= maximum.x, point.y <= maximum.y else { return false }

        func inside(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ c: SIMD2<Float>) -> Bool {
            func edge(_ p: SIMD2<Float>, _ q: SIMD2<Float>) -> Float {
                (q.x - p.x) * (point.y - p.y) - (q.y - p.y) * (point.x - p.x)
            }
            let e1 = edge(a, b)
            let e2 = edge(b, c)
            let e3 = edge(c, a)
            return (e1 >= 0 && e2 >= 0 && e3 >= 0) || (e1 <= 0 && e2 <= 0 && e3 <= 0)
        }
        for j in 0..<(sim.rows - 1) {
            for i in 0..<(sim.cols - 1) {
                let a = projected[sim.index(i, j)]
                let b = projected[sim.index(i + 1, j)]
                let c = projected[sim.index(i + 1, j + 1)]
                let d = projected[sim.index(i, j + 1)]
                if inside(a, b, c) || inside(a, c, d) { return true }
            }
        }
        return false
    }

    func covers(_ point: CGPoint) -> Bool {
        visibleTriangles(contains: SIMD2(Float(point.x), Float(point.y)))
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        covers(convert(point, from: superview)) ? self : nil
    }

    private func nearestParticle(to point: CGPoint) -> Int {
        let s = SIMD2(Float(point.x), Float(point.y))
        var best = 0
        var bestScore = Float.greatestFiniteMagnitude
        for i in sim.position.indices {
            let distance = simd_distance(project(sim.position[i]), s)
            let score = distance - sim.position[i].z * 0.8
            if score < bestScore {
                bestScore = score
                best = i
            }
        }
        return best
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseMoved(with event: NSEvent) {
        guard !grabbing, script == nil else { return }
        let point = convert(event.locationInWindow, from: nil)
        let near = sim.corners.first { simd_distance(project(sim.position[$0]), SIMD2(Float(point.x), Float(point.y))) < 46 && sim.position[$0].z < 2 }
        if let near {
            if hovered != near {
                hovered = near
                sim.pinned = near
                smoothedTarget = sim.position[near]
            }
            let base = sim.position[near]
            rawTarget = SIMD3(base.x, base.y, 16)
            wake()
        } else {
            releaseHover()
        }
    }

    override func mouseExited(with event: NSEvent) {
        releaseHover()
    }

    private func releaseHover() {
        guard let hovered, !grabbing else { return }
        if sim.pinned == hovered { sim.pinned = nil }
        self.hovered = nil
        wake()
    }

    override func mouseDown(with event: NSEvent) {
        script = nil
        settleUntil = 0
        let point = convert(event.locationInWindow, from: nil)
        let particle = hovered ?? nearestParticle(to: point)
        hovered = nil
        grabbing = true
        sim.pinned = particle
        smoothedTarget = sim.position[particle]
        rawTarget = unproject(point, height: 48)
        wake()
    }

    override func mouseDragged(with event: NSEvent) {
        guard grabbing else { return }
        rawTarget = unproject(convert(event.locationInWindow, from: nil), height: 48)
    }

    override func mouseUp(with event: NSEvent) {
        grabbing = false
        sim.pinned = nil
        wake()
    }

    func toggle() {
        if sim.isFlat {
            foldOpen()
        } else {
            layFlat()
        }
    }

    func layFlat() {
        script = nil
        grabbing = false
        sim.pinned = nil
        sim.settleTarget = sim.flatOffset()
        settleUntil = CACurrentMediaTime() + 0.9
        wake()
    }

    private var inwardCorner: (corner: Int, opposite: Int) {
        let corners = sim.corners
        let middle = eye
        var best = 0
        var bestDistance = Float.greatestFiniteMagnitude
        for k in 0..<4 {
            let o = sim.position[corners[(k + 2) % 4]]
            let distance = simd_distance(SIMD2(o.x, o.y), middle)
            if distance < bestDistance {
                bestDistance = distance
                best = k
            }
        }
        return (corners[best], corners[(best + 2) % 4])
    }

    func foldOpen() {
        let (corner, opposite) = inwardCorner
        let from = sim.position[corner]
        let towards = sim.position[opposite]
        let to = SIMD3(from.x + (towards.x - from.x) * 0.92, from.y + (towards.y - from.y) * 0.92, 30)
        run(Script(particle: corner, from: from, to: to, lift: 150, start: CACurrentMediaTime(), duration: 1.0))
    }

    func tuck() {
        guard !grabbing, script == nil, sim.isFlat else { return }
        let (corner, opposite) = inwardCorner
        let from = sim.position[corner]
        let towards = sim.position[opposite]
        let to = SIMD3(from.x + (towards.x - from.x) * 0.06, from.y + (towards.y - from.y) * 0.06, 0)
        run(Script(particle: corner, from: from, to: to, lift: 90, start: CACurrentMediaTime(), duration: 0.7))
    }

    private func run(_ script: Script) {
        hovered = nil
        self.script = script
        wake()
    }

    func footprint() -> CGRect {
        let offset = sim.flatOffset()
        let size = CGSize(width: CGFloat(Self.size.x), height: CGFloat(Self.size.y))
        return CGRect(x: CGFloat(offset.x) - size.width / 2, y: CGFloat(offset.y) - size.height / 2, width: size.width, height: size.height)
    }
}
