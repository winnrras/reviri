import AVFoundation
import SwiftUI

/// Startup screen: plays the logo animation (LogoAnimation.mp4 or .mov in the app folder) once,
/// then fades into the app. Tap to skip. Without the video file it shows the wordmark briefly.
struct SplashView: View {
    var onFinished: () -> Void

    private static let videoURL = ["mp4", "mov", "m4v"].lazy
        .compactMap { Bundle.main.url(forResource: "LogoAnimation", withExtension: $0) }
        .first
    private static let maxSeconds = 3.5     // never hold the app longer than this
    /// The video's own background (#F7F6F1), so the edges blend into it.
    private static let videoCream = Color(red: 0xF7 / 255, green: 0xF6 / 255, blue: 0xF1 / 255)

    @State private var finished = false
    @State private var showWordmark = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            (Self.videoURL != nil && !reduceMotion ? Self.videoCream : Theme.background).ignoresSafeArea()
            if let url = Self.videoURL, !reduceMotion {
                LoopFreeVideo(url: url) { finish() }
                    .ignoresSafeArea()
            } else {
                VStack(spacing: 16) {
                    Image("SproutIllustration").resizable().frame(width: 80, height: 88)
                    Text("Reviri").font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.text)
                    Text("Use it before you lose it").font(Theme.subhead).foregroundStyle(Theme.secondaryText)
                }
                .opacity(showWordmark ? 1 : 0)
                .scaleEffect(showWordmark ? 1 : 0.94)
                .onAppear {
                    withAnimation(.easeOut(duration: 0.6)) { showWordmark = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { finish() }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { finish() }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.maxSeconds) { finish() }
        }
        .accessibilityElement()
        .accessibilityLabel("Reviri")
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        onFinished()
    }
}

/// Plays a video once, filling the screen without controls, and reports when it ends.
private struct LoopFreeVideo: UIViewRepresentable {
    let url: URL
    var onEnd: () -> Void

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        let player = AVPlayer(url: url)
        player.isMuted = true                     // a startup animation shouldn't make sound
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill   // fill the taller phone; only empty cream is trimmed
        context.coordinator.observe(player, onEnd: onEnd)
        player.play()
        return view
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        private var token: NSObjectProtocol?
        func observe(_ player: AVPlayer, onEnd: @escaping () -> Void) {
            token = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                                                           object: player.currentItem, queue: .main) { _ in onEnd() }
        }
        deinit { if let token { NotificationCenter.default.removeObserver(token) } }
    }

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
