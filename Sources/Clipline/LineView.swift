import SwiftUI

struct LineView: View {
    @ObservedObject var store: ShotStore

    private let ropeTop: CGFloat = 26
    private let pictureHeight: CGFloat = 112
    private let spacing: CGFloat = 30
    private let margin: CGFloat = 48

    var body: some View {
        GeometryReader { geometry in
            let placed = place(in: geometry.size.width)
            let width = max(geometry.size.width, placed.last.map { $0.x + $0.size.width / 2 + margin } ?? 0)
            let sag = min(30, width * 0.014)

            ZStack(alignment: .topLeading) {
                backdrop

                ScrollView(.horizontal, showsIndicators: false) {
                    ZStack(alignment: .topLeading) {
                        Rope(top: ropeTop, sag: sag)
                            .frame(width: width, height: geometry.size.height)

                        ForEach(placed, id: \.shot.id) { item in
                            let cardHeight = item.size.height + ShotCard.border + ShotCard.caption
                            let y = ropeTop + Rope.drop(at: item.x, width: width, sag: sag) + 6
                            ShotCard(
                                shot: item.shot,
                                image: item.image,
                                imageSize: item.size,
                                restAngle: angle(for: item.shot),
                                actions: store.actions(for: item.shot)
                            )
                            .position(x: item.x, y: y + cardHeight / 2)
                        }
                    }
                    .frame(width: width, height: geometry.size.height, alignment: .topLeading)
                }

                if store.shots.isEmpty {
                    Text("Nothing on the line yet. Take a screenshot with Shift Command 4.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(.regularMaterial))
                        .frame(maxWidth: .infinity)
                        .padding(.top, ropeTop + sag + 22)
                }
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: store.shots.map(\.id))
    }

    private var backdrop: some View {
        Blur()
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black.opacity(0.85), location: 0.55),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .allowsHitTesting(false)
    }

    private struct Placed {
        let shot: Shot
        let image: NSImage?
        let size: CGSize
        let x: CGFloat
    }

    private func place(in available: CGFloat) -> [Placed] {
        var sized: [(Shot, NSImage?, CGSize)] = []
        for shot in store.shots {
            let image = store.thumbnail(for: shot)
            let aspect = image.map { $0.size.width / max($0.size.height, 1) } ?? 1.5
            let width = min(max(pictureHeight * aspect, 74), 210)
            sized.append((shot, image, CGSize(width: width, height: pictureHeight)))
        }

        let total = sized.reduce(0) { $0 + $1.2.width + ShotCard.border * 2 } + spacing * CGFloat(max(sized.count - 1, 0))
        var x = max(margin, (available - total) / 2)
        return sized.map { shot, image, size in
            let cardWidth = size.width + ShotCard.border * 2
            defer { x += cardWidth + spacing }
            return Placed(shot: shot, image: image, size: size, x: x + cardWidth / 2)
        }
    }

    private func angle(for shot: Shot) -> Double {
        let seed = shot.url.lastPathComponent.unicodeScalars.reduce(7) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return Double(seed % 70) / 10 - 3.5
    }
}

struct Rope: View {
    let top: CGFloat
    let sag: CGFloat

    static func drop(at x: CGFloat, width: CGFloat, sag: CGFloat) -> CGFloat {
        let t = min(max(x / max(width, 1), 0), 1)
        return 4 * sag * t * (1 - t)
    }

    var body: some View {
        Canvas { context, size in
            var path = Path()
            path.move(to: CGPoint(x: 0, y: top))
            path.addQuadCurve(
                to: CGPoint(x: size.width, y: top),
                control: CGPoint(x: size.width / 2, y: top + sag * 2)
            )
            var shadow = context
            shadow.translateBy(x: 0, y: 2.5)
            shadow.stroke(path, with: .color(.black.opacity(0.16)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            context.stroke(path, with: .color(Color(red: 0.83, green: 0.76, blue: 0.64)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            context.stroke(path, with: .color(Color(red: 0.6, green: 0.51, blue: 0.39)), style: StrokeStyle(lineWidth: 3, lineCap: .butt, dash: [2, 3.5]))
        }
        .allowsHitTesting(false)
    }
}

struct Blur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
