import AppKit
import AVFoundation
import Darwin

private enum FishKind: Int {
    case tetra, gourami, angelfish, guppy
}

private struct Fish {
    var kind: FishKind
    var position: CGPoint
    var velocity: CGVector
    var width: CGFloat
    var cruiseSpeed: CGFloat
    var phase: Double
    var depth: CGFloat
}

private struct Bubble {
    var x: CGFloat
    var y: CGFloat
    var radius: CGFloat
    var speed: CGFloat
}

@MainActor
private final class AquariumView: NSView {
    private let fishImages: [NSImage]
    private let desktopFrame: NSRect
    private var fish: [Fish] = []
    private var bubbles: [Bubble] = []
    private var lastTick = ProcessInfo.processInfo.systemUptime
    private var timer: Timer?
    private var elapsed = 0.0

    override var isFlipped: Bool { true }

    init(frame: NSRect, desktopFrame: NSRect, fishImages: [NSImage]) {
        self.desktopFrame = desktopFrame
        self.fishImages = fishImages
        super.init(frame: frame)
        wantsLayer = true
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor
        seedLife()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    required init?(coder: NSCoder) { fatalError("Use init(frame:desktopFrame:fishImages:)") }

    private func seedLife() {
        for (kind, count) in [(FishKind.tetra, 16), (.gourami, 3), (.angelfish, 2), (.guppy, 6)] {
            for i in 0..<count {
                let widthRange: ClosedRange<CGFloat>
                let speedRange: ClosedRange<CGFloat>
                switch kind {
                case .tetra:
                    widthRange = 45...64
                    speedRange = 22...38
                case .gourami:
                    widthRange = 87...110
                    speedRange = 11...20
                case .angelfish:
                    widthRange = 106...137
                    speedRange = 8...15
                case .guppy:
                    widthRange = 63...82
                    speedRange = 18...31
                }
                let direction: CGFloat = i.isMultiple(of: 2) ? 1 : -1
                let speed = CGFloat.random(in: speedRange)
                fish.append(Fish(
                    kind: kind,
                    position: CGPoint(
                        x: CGFloat.random(in: 0...max(bounds.width, 1)),
                        y: bounds.height * CGFloat.random(in: 0.20...0.72)
                    ),
                    velocity: CGVector(dx: direction * speed, dy: CGFloat.random(in: -5...5)),
                    width: CGFloat.random(in: widthRange),
                    cruiseSpeed: speed,
                    phase: Double.random(in: 0...(Double.pi * 2)),
                    depth: CGFloat.random(in: 0.76...1.0)
                ))
            }
        }
        for _ in 0..<32 {
            bubbles.append(Bubble(
                x: CGFloat.random(in: 0...max(bounds.width, 1)),
                y: CGFloat.random(in: 0...max(bounds.height, 1)),
                radius: CGFloat.random(in: 0.8...2.7),
                speed: CGFloat.random(in: 5...17)
            ))
        }
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = min(max(now - lastTick, 0), 0.06)
        lastTick = now
        elapsed += dt

        let cursor = NSEvent.mouseLocation
        let pointer = CGPoint(x: cursor.x - desktopFrame.minX, y: desktopFrame.maxY - cursor.y)
        let pointerIsHere = desktopFrame.contains(cursor)

        for i in fish.indices {
            let dx = fish[i].position.x - pointer.x
            let dy = fish[i].position.y - pointer.y
            let distance = max(sqrt(dx * dx + dy * dy), 1)
            var ax: CGFloat = 0
            var ay: CGFloat = 0

            // Fish scatter from the cursor without taking mouse input from the desktop.
            let reactionRadius: CGFloat = fish[i].kind == .angelfish ? 190 : 145
            if pointerIsHere && distance < reactionRadius {
                let force = pow((reactionRadius - distance) / reactionRadius, 2) * (fish[i].kind == .angelfish ? 170 : 290)
                ax += dx / distance * force
                ay += dy / distance * force
            }

            let swimRate = fish[i].kind == .angelfish ? 0.45 : 0.9
            let swim = sin(elapsed * swimRate + fish[i].phase)
            ay += CGFloat(swim) * (fish[i].kind == .angelfish ? 2.5 : 5)
            if abs(fish[i].velocity.dx) < fish[i].cruiseSpeed * 0.7 {
                ax += fish[i].velocity.dx >= 0 ? 9 : -9
            }

            if fish[i].position.x < 35 { ax += 80 }
            if fish[i].position.x > bounds.width - 35 { ax -= 80 }
            if fish[i].position.y < bounds.height * 0.14 { ay += 36 }
            if fish[i].position.y > bounds.height * 0.79 { ay -= 36 }

            fish[i].velocity.dx += ax * dt
            fish[i].velocity.dy += ay * dt
            fish[i].velocity.dx *= CGFloat(1 - 0.14 * dt)
            fish[i].velocity.dy *= CGFloat(1 - 0.8 * dt)

            let speed = hypot(fish[i].velocity.dx, fish[i].velocity.dy)
            let maximumSpeed = max(fish[i].cruiseSpeed * 3, 48)
            if speed > maximumSpeed {
                fish[i].velocity.dx *= maximumSpeed / speed
                fish[i].velocity.dy *= maximumSpeed / speed
            }
            fish[i].position.x += fish[i].velocity.dx * dt
            fish[i].position.y += fish[i].velocity.dy * dt

            if fish[i].position.x < -80 {
                fish[i].position.x = -80
                fish[i].velocity.dx = abs(fish[i].velocity.dx)
            } else if fish[i].position.x > bounds.width + 80 {
                fish[i].position.x = bounds.width + 80
                fish[i].velocity.dx = -abs(fish[i].velocity.dx)
            }
        }

        for i in bubbles.indices {
            bubbles[i].y -= bubbles[i].speed * dt
            bubbles[i].x += CGFloat(sin(elapsed + Double(i))) * CGFloat(dt) * 2
            if bubbles[i].y < -10 {
                bubbles[i].y = bounds.height + 10
                bubbles[i].x = CGFloat.random(in: 0...max(bounds.width, 1))
            }
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current else { return }
        context.imageInterpolation = .high

        for bubble in bubbles {
            NSColor(calibratedWhite: 0.87, alpha: 0.23).setStroke()
            let rect = NSRect(x: bubble.x, y: bubble.y, width: bubble.radius * 2, height: bubble.radius * 2)
            let path = NSBezierPath(ovalIn: rect)
            path.lineWidth = 0.7
            path.stroke()
        }

        for individual in fish.sorted(by: { $0.depth < $1.depth }) {
            let fishImage = fishImages[individual.kind.rawValue]
            let width = individual.width * individual.depth
            let height = width * fishImage.size.height / fishImage.size.width
            context.saveGraphicsState()
            let cg = context.cgContext
            cg.translateBy(x: individual.position.x, y: individual.position.y)
            if individual.velocity.dx < 0 { cg.scaleBy(x: -1, y: 1) }
            fishImage.draw(
                in: NSRect(x: -width / 2, y: -height / 2, width: width, height: height),
                from: .zero,
                operation: .sourceOver,
                fraction: individual.depth * 0.93,
                respectFlipped: true,
                hints: nil
            )
            context.restoreGraphicsState()
        }
    }
}

@MainActor
private final class AquariumApp: NSObject, NSApplicationDelegate {
    private var windows: [NSWindow] = []
    private var players: [AVQueuePlayer] = []
    private var loopers: [AVPlayerLooper] = []
    private var signalSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let assets = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("assets")
        let videoURL = assets.appendingPathComponent("aquarium-loop.mp4")
        let fishNames = ["neon-tetra.png", "honey-gourami.png", "silver-angelfish.png", "fancy-guppy.png"]
        let fishImages = fishNames.compactMap { NSImage(contentsOf: assets.appendingPathComponent($0)) }
        guard FileManager.default.fileExists(atPath: videoURL.path), fishImages.count == fishNames.count else {
            fputs("fish: missing aquarium artwork\n", stderr)
            NSApp.terminate(nil)
            return
        }

        for screen in NSScreen.screens {
            let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false, screen: screen)
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            window.ignoresMouseEvents = true
            window.isOpaque = true
            window.backgroundColor = .black
            window.hasShadow = false

            let contentFrame = NSRect(origin: .zero, size: screen.frame.size)
            let container = NSView(frame: contentFrame)
            container.wantsLayer = true
            container.layer?.backgroundColor = NSColor.black.cgColor

            let player = AVQueuePlayer()
            player.isMuted = true
            let looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: videoURL))
            let videoView = NSView(frame: contentFrame)
            videoView.wantsLayer = true
            let videoLayer = AVPlayerLayer(player: player)
            videoLayer.frame = videoView.bounds
            videoLayer.videoGravity = .resizeAspectFill
            videoView.layer = videoLayer
            videoView.autoresizingMask = [.width, .height]
            container.addSubview(videoView)

            let aquarium = AquariumView(frame: contentFrame, desktopFrame: screen.frame, fishImages: fishImages)
            aquarium.autoresizingMask = [.width, .height]
            container.addSubview(aquarium)
            window.contentView = container
            window.orderFrontRegardless()
            windows.append(window)
            players.append(player)
            loopers.append(looper)
            player.play()
        }

        for number in [SIGINT, SIGTERM] {
            Darwin.signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler { NSApp.terminate(nil) }
            source.resume()
            signalSources.append(source)
        }
        print("Aquarium is swimming behind your desktop icons. Press Control-C to stop.")
        fflush(stdout)
    }

    func applicationWillTerminate(_ notification: Notification) {
        players.forEach { $0.pause() }
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        loopers.removeAll()
        players.removeAll()
    }
}

@main
@MainActor
private enum Main {
    static func main() {
        if CommandLine.arguments.contains("--check") {
            let assets = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("assets")
            let names = ["aquarium-loop.mp4", "neon-tetra.png", "honey-gourami.png", "silver-angelfish.png", "fancy-guppy.png"]
            let missing = names.filter { !FileManager.default.fileExists(atPath: assets.appendingPathComponent($0).path) }
            if missing.isEmpty {
                print("Aquarium assets are present.")
            } else {
                fputs("Missing aquarium assets: \(missing.joined(separator: ", "))\n", stderr)
                Darwin.exit(1)
            }
            return
        }
        let app = NSApplication.shared
        let delegate = AquariumApp()
        app.delegate = delegate
        app.setActivationPolicy(.prohibited)
        app.run()
    }
}
