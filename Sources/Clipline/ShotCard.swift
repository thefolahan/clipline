import SwiftUI

struct ShotCard: View {
    let shot: Shot
    let image: NSImage?
    let imageSize: CGSize
    let restAngle: Double
    let actions: ShotActions

    @State private var hovering = false
    @State private var swing: Double = 0
    @State private var dropped = false
    @State private var feedback: String?

    static let border: CGFloat = 5
    static let caption: CGFloat = 18

    var body: some View {
        VStack(spacing: 0) {
            picture
                .frame(width: imageSize.width, height: imageSize.height)
                .clipShape(RoundedRectangle(cornerRadius: 1.5))
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                HStack(spacing: 4) {
                    if shot.pinned {
                        Image(systemName: "pin.fill").font(.system(size: 8))
                    }
                    Text(age)
                    Spacer(minLength: 0)
                    if shot.text?.isEmpty == false {
                        Image(systemName: "text.viewfinder").font(.system(size: 9))
                    }
                }
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(Color(white: 0.42))
                .padding(.horizontal, 2)
            }
            .frame(width: imageSize.width, height: Self.caption)
        }
        .padding([.top, .horizontal], Self.border)
        .background(
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color(white: 0.985))
                .shadow(color: .black.opacity(hovering ? 0.32 : 0.22), radius: hovering ? 10 : 6, y: hovering ? 7 : 4)
        )
        .overlay(alignment: .topTrailing) {
            if hovering {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(.black.opacity(0.62)))
                    .padding(8)
                    .transition(.opacity.combined(with: .scale(scale: 0.6)))
            }
        }
        .overlay {
            if let feedback {
                Text(feedback)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(.black.opacity(0.7)))
                    .transition(.opacity.combined(with: .scale(scale: 0.85)))
            }
        }
        .overlay {
            GrabArea(shot: shot, image: image, actions: actions, onHover: hover, onFeedback: flash)
        }
        .overlay(alignment: .top) {
            Peg(pinned: shot.pinned).offset(y: -15).allowsHitTesting(false)
        }
        .rotationEffect(.degrees(restAngle + swing), anchor: .top)
        .scaleEffect(hovering ? 1.035 : 1, anchor: .top)
        .offset(y: dropped ? 0 : -170)
        .opacity(dropped ? 1 : 0)
        .onAppear {
            swing = restAngle >= 0 ? -15 : 15
            withAnimation(.spring(response: 0.42, dampingFraction: 0.72)) { dropped = true }
            withAnimation(.interpolatingSpring(stiffness: 60, damping: 3.2)) { swing = 0 }
        }
        .onChange(of: shot.pinned) {
            nudge(5)
        }
    }

    private var age: String {
        let seconds = Date().timeIntervalSince(shot.added)
        if seconds < 60 { return "Just now" }
        if seconds < 3600 { return "\(Int(seconds / 60)) min ago" }
        if seconds < 86400 { return "\(Int(seconds / 3600)) h ago" }
        return "\(Int(seconds / 86400)) d ago"
    }

    @ViewBuilder
    private var picture: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
        } else {
            Rectangle().fill(Color(white: 0.88))
        }
    }

    private func hover(_ inside: Bool) {
        withAnimation(.easeOut(duration: 0.16)) { hovering = inside }
        if inside { nudge(3.5) }
    }

    private func nudge(_ degrees: Double) {
        swing = restAngle >= 0 ? degrees : -degrees
        withAnimation(.interpolatingSpring(stiffness: 80, damping: 3.5)) { swing = 0 }
    }

    private func flash(_ message: String) {
        withAnimation(.easeOut(duration: 0.14)) { feedback = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            withAnimation(.easeIn(duration: 0.2)) {
                if feedback == message { feedback = nil }
            }
        }
    }
}

struct Peg: View {
    let pinned: Bool

    var body: some View {
        let colors: [Color] = pinned
            ? [Color(red: 0.93, green: 0.33, blue: 0.29), Color(red: 0.72, green: 0.17, blue: 0.16)]
            : [Color(red: 0.86, green: 0.70, blue: 0.50), Color(red: 0.66, green: 0.49, blue: 0.31)]
        ZStack {
            RoundedRectangle(cornerRadius: 2.5)
                .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                .frame(width: 11, height: 30)
                .shadow(color: .black.opacity(0.28), radius: 1.5, y: 1)
            Rectangle()
                .fill(.black.opacity(0.22))
                .frame(width: 1, height: 26)
            Capsule()
                .fill(Color(white: 0.75))
                .frame(width: 13, height: 3)
                .offset(y: 3)
        }
    }
}
