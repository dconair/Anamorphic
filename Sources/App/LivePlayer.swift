import SwiftUI
import AVFoundation

#if os(macOS)
import AppKit

/// Zeigt einen AVPlayer. Die Bilder kommen bereits fertig aus der Anamorphic-Pipeline (AVVideoComposition).
struct PlayerLayerView: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> PlayerNSView {
        let v = PlayerNSView()
        v.playerLayer.player = player
        return v
    }
    func updateNSView(_ v: PlayerNSView, context: Context) { v.playerLayer.player = player }
}

final class PlayerNSView: NSView {
    init() {
        super.init(frame: .zero)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) wird nicht verwendet") }
    override func makeBackingLayer() -> CALayer { AVPlayerLayer() }
    var playerLayer: AVPlayerLayer {
        let l = layer as! AVPlayerLayer
        l.videoGravity = .resizeAspect
        return l
    }
}
#else
import UIKit

struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer
    func makeUIView(context: Context) -> PlayerUIView {
        let v = PlayerUIView()
        v.playerLayer.player = player
        return v
    }
    func updateUIView(_ v: PlayerUIView, context: Context) { v.playerLayer.player = player }
}

final class PlayerUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer {
        let l = layer as! AVPlayerLayer
        l.videoGravity = .resizeAspect
        return l
    }
}
#endif

/// Von mehreren Threads gelesene Einstellungen für die Live-Wiedergabe.
final class LiveBox: @unchecked Sendable {
    private let lock = NSLock()
    private var settings = AnamorphicSettings()
    private var lut: CubeLUT?

    func set(_ s: AnamorphicSettings, lut: CubeLUT?) {
        lock.lock(); defer { lock.unlock() }
        settings = s
        self.lut = lut
    }

    func get() -> (AnamorphicSettings, CubeLUT?) {
        lock.lock(); defer { lock.unlock() }
        return (settings, lut)
    }
}
