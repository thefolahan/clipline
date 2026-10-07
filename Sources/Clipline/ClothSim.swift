import simd

final class ClothSim {
    let cols: Int
    let rows: Int
    let spacing: SIMD2<Float>
    private(set) var position: [SIMD3<Float>]
    private var previous: [SIMD3<Float>]
    let rest: [SIMD2<Float>]

    private struct Link {
        let a: Int32
        let b: Int32
        let length: Float
        let stiffness: Float
    }
    private var links: [Link] = []

    var pinned: Int?
    var pinTarget = SIMD3<Float>.zero
    var settleTarget: SIMD2<Float>?
    var settleStrength: Float = 0

    private let gravity: Float = -2600
    private let thickness: Float = 4.5
    private let iterations = 8

    private var resting: [Bool]
    private var cellHead: [Int32]
    private var cellNext: [Int32]
    private let cellCount = 4096

    init(size: SIMD2<Float>, center: SIMD2<Float>, cols: Int = 46, rows: Int = 29) {
        self.cols = cols
        self.rows = rows
        spacing = SIMD2(size.x / Float(cols - 1), size.y / Float(rows - 1))

        var rest: [SIMD2<Float>] = []
        for j in 0..<rows {
            for i in 0..<cols {
                rest.append(SIMD2(Float(i) * spacing.x - size.x / 2, Float(j) * spacing.y - size.y / 2))
            }
        }
        self.rest = rest
        position = rest.map { SIMD3($0.x + center.x, $0.y + center.y, 0) }
        previous = position
        cellHead = Array(repeating: -1, count: cellCount)
        cellNext = Array(repeating: -1, count: cols * rows)
        resting = Array(repeating: false, count: cols * rows)

        func link(_ i: Int, _ j: Int, _ di: Int, _ dj: Int, _ stiffness: Float) {
            let ni = i + di
            let nj = j + dj
            guard ni >= 0, ni < cols, nj >= 0, nj < rows else { return }
            let a = j * cols + i
            let b = nj * cols + ni
            links.append(Link(a: Int32(a), b: Int32(b), length: simd_distance(rest[a], rest[b]), stiffness: stiffness))
        }
        for j in 0..<rows {
            for i in 0..<cols {
                link(i, j, 1, 0, 1)
                link(i, j, 0, 1, 1)
                link(i, j, 1, 1, 0.9)
                link(i, j, 1, -1, 0.9)
                link(i, j, 2, 0, 0.06)
                link(i, j, 0, 2, 0.06)
            }
        }
    }

    func index(_ i: Int, _ j: Int) -> Int { j * cols + i }

    var corners: [Int] {
        [index(0, 0), index(cols - 1, 0), index(cols - 1, rows - 1), index(0, rows - 1)]
    }

    func step(_ dt: Float) -> Float {
        let count = position.count
        var motion: Float = 0

        position.withUnsafeMutableBufferPointer { p in
            previous.withUnsafeMutableBufferPointer { q in
                let drag: Float = 0.996
                for i in 0..<count where i != pinned {
                    let velocity = (p[i] - q[i]) * drag
                    q[i] = p[i]
                    p[i] += velocity
                    p[i].z += gravity * dt * dt
                }

                links.withUnsafeBufferPointer { l in
                    for _ in 0..<iterations {
                        if let pin = pinned { p[pin] = pinTarget }
                        for link in l {
                            let a = Int(link.a)
                            let b = Int(link.b)
                            let delta = p[b] - p[a]
                            let distance = simd_length(delta)
                            guard distance > 0.0001 else { continue }
                            let correction = delta * ((distance - link.length) / distance * link.stiffness)
                            let aPinned = a == pinned
                            let bPinned = b == pinned
                            if aPinned {
                                p[b] -= correction
                            } else if bPinned {
                                p[a] += correction
                            } else {
                                p[a] += correction * 0.5
                                p[b] -= correction * 0.5
                            }
                        }
                        for i in 0..<count where p[i].z < 0 {
                            p[i].z = 0
                        }
                    }
                }

                for i in 0..<count { resting[i] = false }
                separateLayers(p)

                for i in 0..<count {
                    if p[i].z < 0 { p[i].z = 0 }
                    if (p[i].z < 0.6 || resting[i]) && i != pinned {
                        q[i].x = p[i].x - (p[i].x - q[i].x) * 0.25
                        q[i].y = p[i].y - (p[i].y - q[i].y) * 0.25
                    }
                }

                if let target = settleTarget, settleStrength > 0 {
                    for i in 0..<count {
                        let goal = SIMD3(target.x + rest[i].x, target.y + rest[i].y, 0)
                        p[i] += (goal - p[i]) * settleStrength
                        q[i] += (goal - q[i]) * settleStrength
                    }
                }

                for i in 0..<count {
                    motion = max(motion, simd_length_squared(p[i] - q[i]))
                }
            }
        }
        return motion.squareRoot()
    }

    private func separateLayers(_ p: UnsafeMutableBufferPointer<SIMD3<Float>>) {
        let radius = max(spacing.x, spacing.y) * 0.85
        let radiusSquared = radius * radius
        let cell = radius
        let count = p.count

        for i in 0..<cellHead.count { cellHead[i] = -1 }
        func key(_ x: Int, _ y: Int) -> Int {
            ((x &* 73_856_093) ^ (y &* 19_349_663)) & (cellCount - 1)
        }
        for i in 0..<count {
            let k = key(Int((p[i].x / cell).rounded(.down)), Int((p[i].y / cell).rounded(.down)))
            cellNext[i] = cellHead[k]
            cellHead[k] = Int32(i)
        }

        for i in 0..<count {
            let ci = i % cols
            let cj = i / cols
            let cx = Int((p[i].x / cell).rounded(.down))
            let cy = Int((p[i].y / cell).rounded(.down))
            for ox in -1...1 {
                for oy in -1...1 {
                    var other = cellHead[key(cx + ox, cy + oy)]
                    while other >= 0 {
                        let o = Int(other)
                        other = cellNext[o]
                        guard o > i else { continue }
                        if abs(o % cols - ci) <= 2 && abs(o / cols - cj) <= 2 { continue }
                        let dx = p[o].x - p[i].x
                        let dy = p[o].y - p[i].y
                        guard dx * dx + dy * dy < radiusSquared else { continue }
                        let dz = p[o].z - p[i].z
                        guard abs(dz) < thickness, abs(dz) > 0.01 else { continue }
                        let push = thickness - abs(dz)
                        let (upper, lower) = dz > 0 ? (o, i) : (i, o)
                        resting[upper] = true
                        if p[lower].z < 0.6 || lower == pinned {
                            if upper != pinned { p[upper].z += push }
                        } else if upper == pinned {
                            p[lower].z -= push
                        } else {
                            p[upper].z += push * 0.5
                            p[lower].z -= push * 0.5
                        }
                    }
                }
            }
        }
    }

    func normals() -> [SIMD3<Float>] {
        var result = [SIMD3<Float>](repeating: SIMD3(0, 0, 1), count: position.count)
        for j in 0..<rows {
            for i in 0..<cols {
                let left = position[index(max(i - 1, 0), j)]
                let right = position[index(min(i + 1, cols - 1), j)]
                let down = position[index(i, max(j - 1, 0))]
                let up = position[index(i, min(j + 1, rows - 1))]
                let n = simd_cross(right - left, up - down)
                let length = simd_length(n)
                result[index(i, j)] = length > 0 ? n / length : SIMD3(0, 0, 1)
            }
        }
        return result
    }

    func flatOffset() -> SIMD2<Float> {
        let normal = normals()
        var sum = SIMD2<Float>.zero
        var weight: Float = 0
        for i in position.indices where position[i].z < 1 && normal[i].z > 0.9 {
            sum += SIMD2(position[i].x, position[i].y) - rest[i]
            weight += 1
        }
        if weight < 20 {
            for i in position.indices {
                sum += SIMD2(position[i].x, position[i].y) - rest[i]
            }
            weight = Float(position.count)
        }
        return sum / weight
    }

    var isFlat: Bool {
        position.allSatisfy { $0.z < 1 }
    }

    func translate(by offset: SIMD2<Float>) {
        for i in position.indices {
            position[i].x += offset.x
            position[i].y += offset.y
            previous[i].x += offset.x
            previous[i].y += offset.y
        }
    }
}
