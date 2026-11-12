// Drinking Bird — presses Enter (or ⌘Enter) whenever the target app is in front,
// and a drinking bird dips its beak into a glass of water / onto a keyboard each time.

import SwiftUI
import AppKit
import ApplicationServices

// MARK: - Model

enum PeckTarget: String, CaseIterable, Identifiable {
    case water = "Glass of water"
    case keyboard = "Keyboard"
    var id: String { rawValue }
}

enum KeyMode: String, CaseIterable, Identifiable {
    case cmdEnter = "⌘ + Enter"
    case enter = "Enter"
    var id: String { rawValue }
}

@MainActor
final class Pecker: ObservableObject {
    @Published var running = false
    @Published var interval: Double = 1.0 { didSet { if running { schedule() } } }
    @Published var targetApp = "Claude"
    @Published var keyMode: KeyMode = .cmdEnter
    @Published var target: PeckTarget = .water
    @Published var presses = 0
    @Published var status = "Stopped"
    @Published var lastPeck: Date? = nil
    @Published var trusted = AXIsProcessTrusted()

    private var timer: Timer?

    func toggle() { running ? stop() : start() }

    func start() {
        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        trusted = AXIsProcessTrustedWithOptions(opts)
        running = true
        status = "Waiting for \(targetApp)…"
        schedule()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        running = false
        status = "Stopped"
    }

    private func schedule() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        trusted = AXIsProcessTrusted()
        let front = NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"
        guard front == targetApp else {
            status = "Waiting for \(targetApp)… (front: \(front))"
            return
        }
        guard trusted else {
            status = "Needs Accessibility permission"
            return
        }
        pressEnter()
        presses += 1
        lastPeck = Date()
        status = "Peck! → \(targetApp)"
    }

    private func pressEnter() {
        let src = CGEventSource(stateID: .hidSystemState)
        let flags: CGEventFlags = keyMode == .cmdEnter ? .maskCommand : []
        let returnKey: CGKeyCode = 36
        let down = CGEvent(keyboardEventSource: src, virtualKey: returnKey, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: returnKey, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Drawing

/// Everything is drawn in a 360 × 290 design space and scaled to fit.
enum BirdArt {
    static let size = CGSize(width: 360, height: 290)
    static let pivot = CGPoint(x: 214, y: 122)
    static let floorY: CGFloat = 274

    // Bird geometry, local to the pivot (rest pose).
    static let headC = CGPoint(x: -110, y: -20)
    static let headR: CGFloat = 24
    static let bulbC = CGPoint(x: 86, y: 16)
    static let bulbR: CGFloat = 30
    static let beakTip = CGPoint(x: -153, y: -5)
    static let dipDegrees: Double = -42

    static func rotate(_ p: CGPoint, _ deg: Double) -> CGPoint {
        let a = deg * .pi / 180
        return CGPoint(x: p.x * cos(a) - p.y * sin(a), y: p.x * sin(a) + p.y * cos(a))
    }

    /// Where the beak tip lands at full dip — targets are placed relative to this.
    static var contact: CGPoint {
        let r = rotate(beakTip, dipDegrees)
        return CGPoint(x: pivot.x + r.x, y: pivot.y + r.y)
    }

    /// 0 = upright, 1 = fully dipped. Fast dip, short hold, then a damped wobble back.
    static func dip(sincePeck e: Double?) -> Double {
        guard let e, e >= 0 else { return 0 }
        if e < 0.2 { let p = e / 0.2; return p * p }
        if e < 0.32 { return 1 }
        let s = e - 0.32
        if s > 3 { return 0 }
        return exp(-4 * s) * cos(9 * s)
    }

    static func isContact(_ e: Double?) -> Bool {
        guard let e else { return false }
        return e > 0.17 && e < 0.4
    }

    static func draw(_ ctx: inout GraphicsContext, canvas: CGSize, time: Double,
                     sincePeck: Double?, running: Bool, interval: Double, target: PeckTarget) {
        let s = min(canvas.width / size.width, canvas.height / size.height)
        ctx.translateBy(x: (canvas.width - size.width * s) / 2, y: (canvas.height - size.height * s) / 2)
        ctx.scaleBy(x: s, y: s)

        let d = dip(sincePeck: sincePeck)
        let sway = running ? 2.5 * sin(time * 2.2) * max(0, 1 - abs(d)) : 0
        let angle = dipDegrees * d + sway

        // Liquid creeping up the neck as the next peck approaches.
        var fill = 0.15
        if running {
            if let e = sincePeck {
                fill = e < 0.4 ? max(0, 1 - e / 0.4) : min(1, (e - 0.4) / max(0.3, interval - 0.4))
            } else {
                fill = 0.5 + 0.5 * sin(time)
            }
        }

        drawRoom(&ctx)
        drawStandBack(&ctx)
        switch target {
        case .water: drawGlassBack(&ctx, sincePeck: sincePeck, time: time)
        case .keyboard: drawKeyboard(&ctx, sincePeck: sincePeck)
        }
        drawBird(&ctx, angle: angle, fill: fill)
        switch target {
        case .water: drawGlassFront(&ctx, sincePeck: sincePeck)
        case .keyboard: drawKeyFlash(&ctx, sincePeck: sincePeck)
        }
        drawStandFront(&ctx)
    }

    // MARK: Room

    static func drawRoom(_ ctx: inout GraphicsContext) {
        let wall = Path(CGRect(x: 0, y: 0, width: size.width, height: floorY))
        ctx.fill(wall, with: .linearGradient(
            Gradient(colors: [Color(red: 0.98, green: 0.86, blue: 0.84), Color(red: 0.93, green: 0.72, blue: 0.74)]),
            startPoint: .zero, endPoint: CGPoint(x: 0, y: floorY)))
        // Wallpaper dots
        for row in 0..<6 {
            for col in 0..<10 {
                let x = CGFloat(col) * 38 + (row.isMultiple(of: 2) ? 10 : 29)
                let y = CGFloat(row) * 40 + 18
                ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 5, height: 5)),
                         with: .color(.white.opacity(0.35)))
            }
        }
        let floor = Path(CGRect(x: 0, y: floorY, width: size.width, height: size.height - floorY))
        ctx.fill(floor, with: .color(Color(red: 0.62, green: 0.42, blue: 0.27)))
        ctx.fill(Path(CGRect(x: 0, y: floorY, width: size.width, height: 3)),
                 with: .color(Color(red: 0.45, green: 0.29, blue: 0.18)))
    }

    // MARK: Stand

    static let woodRed = Color(red: 0.80, green: 0.14, blue: 0.16)
    static let woodRedDark = Color(red: 0.55, green: 0.07, blue: 0.10)

    static func drawStandBack(_ ctx: inout GraphicsContext) {
        var leg = Path()
        leg.move(to: CGPoint(x: pivot.x + 6, y: pivot.y))
        leg.addLine(to: CGPoint(x: pivot.x + 46, y: floorY - 10))
        ctx.stroke(leg, with: .color(woodRedDark), style: StrokeStyle(lineWidth: 11, lineCap: .round))
    }

    static func drawStandFront(_ ctx: inout GraphicsContext) {
        var leg = Path()
        leg.move(to: CGPoint(x: pivot.x - 4, y: pivot.y))
        leg.addLine(to: CGPoint(x: pivot.x - 38, y: floorY - 10))
        ctx.stroke(leg, with: .color(woodRed), style: StrokeStyle(lineWidth: 12, lineCap: .round))
        // Base
        let base = Path(roundedRect: CGRect(x: pivot.x - 62, y: floorY - 14, width: 124, height: 16), cornerRadius: 5)
        ctx.fill(base, with: .color(woodRed))
        ctx.stroke(base, with: .color(woodRedDark), lineWidth: 1.5)
        // Pivot bolt
        let bolt = Path(ellipseIn: CGRect(x: pivot.x - 7, y: pivot.y - 7, width: 14, height: 14))
        ctx.fill(bolt, with: .color(Color(white: 0.8)))
        ctx.stroke(bolt, with: .color(Color(white: 0.35)), lineWidth: 1.5)
    }

    // MARK: Bird

    static func drawBird(_ ctx: inout GraphicsContext, angle: Double, fill: Double) {
        var b = ctx
        b.translateBy(x: pivot.x, y: pivot.y)
        b.rotate(by: .degrees(angle))

        let glass = Color(red: 0.82, green: 0.93, blue: 1.0)
        let liquid = Color(red: 0.86, green: 0.10, blue: 0.20)

        // Tail feathers
        for (i, a) in [-35.0, -10, 15].enumerated() {
            var f = Path()
            let base = CGPoint(x: bulbC.x + 22, y: bulbC.y - 6)
            let r = rotate(CGPoint(x: 30, y: 0), a - 20)
            f.move(to: base)
            f.addQuadCurve(to: CGPoint(x: base.x + r.x, y: base.y + r.y),
                           control: CGPoint(x: base.x + r.x * 0.4, y: base.y + r.y * 0.4 - 10))
            b.stroke(f, with: .color([Color.orange, .yellow, .pink][i]), style: StrokeStyle(lineWidth: 5, lineCap: .round))
        }

        // Neck tube
        var tube = Path()
        tube.move(to: headC)
        tube.addLine(to: bulbC)
        b.stroke(tube, with: .color(Color(white: 0.55)), style: StrokeStyle(lineWidth: 11, lineCap: .round))
        b.stroke(tube, with: .color(glass), style: StrokeStyle(lineWidth: 8, lineCap: .round))

        // Liquid column
        let t = 0.12 + 0.78 * fill
        var column = Path()
        column.move(to: bulbC)
        column.addLine(to: CGPoint(x: bulbC.x + (headC.x - bulbC.x) * t, y: bulbC.y + (headC.y - bulbC.y) * t))
        b.stroke(column, with: .color(liquid), style: StrokeStyle(lineWidth: 4, lineCap: .round))

        // Body bulb
        let bulbRect = CGRect(x: bulbC.x - bulbR, y: bulbC.y - bulbR, width: bulbR * 2, height: bulbR * 2)
        let bulb = Path(ellipseIn: bulbRect)
        b.fill(bulb, with: .color(glass.opacity(0.9)))
        var inner = b
        inner.clip(to: bulb)
        // Liquid stays level-ish with gravity: counter-rotate the fill.
        inner.translateBy(x: bulbC.x, y: bulbC.y)
        inner.rotate(by: .degrees(-angle))
        let level = CGFloat(-4 + 16 * fill)
        inner.fill(Path(CGRect(x: -50, y: level, width: 100, height: 60)), with: .color(liquid))
        b.stroke(bulb, with: .color(Color(white: 0.5)), lineWidth: 2)
        b.fill(Path(ellipseIn: CGRect(x: bulbC.x - 18, y: bulbC.y - 22, width: 12, height: 8)),
               with: .color(.white.opacity(0.85)))

        // Head
        let headRect = CGRect(x: headC.x - headR, y: headC.y - headR, width: headR * 2, height: headR * 2)
        let head = Path(ellipseIn: headRect)
        b.fill(head, with: .radialGradient(
            Gradient(colors: [Color(red: 1, green: 0.35, blue: 0.35), woodRed, woodRedDark]),
            center: CGPoint(x: headC.x - 8, y: headC.y - 9), startRadius: 2, endRadius: headR * 1.3))

        // Beak
        var beak = Path()
        beak.move(to: CGPoint(x: headC.x - 18, y: headC.y - 6))
        beak.addLine(to: beakTip)
        beak.addLine(to: CGPoint(x: headC.x - 14, y: headC.y + 13))
        beak.closeSubpath()
        b.fill(beak, with: .color(Color(red: 1.0, green: 0.78, blue: 0.10)))
        b.stroke(beak, with: .color(Color(red: 0.7, green: 0.45, blue: 0.0)), lineWidth: 1.2)

        // Eye
        let eye = CGPoint(x: headC.x - 8, y: headC.y - 6)
        b.fill(Path(ellipseIn: CGRect(x: eye.x - 6, y: eye.y - 6, width: 12, height: 12)), with: .color(.white))
        b.fill(Path(ellipseIn: CGRect(x: eye.x - 5, y: eye.y - 3, width: 6, height: 6)), with: .color(.black))

        // Top hat
        let hatColor = Color(red: 0.12, green: 0.14, blue: 0.22)
        let crown = Path(roundedRect: CGRect(x: headC.x - 16, y: headC.y - 60, width: 34, height: 40), cornerRadius: 3)
        b.fill(crown, with: .color(hatColor))
        b.fill(Path(CGRect(x: headC.x - 16, y: headC.y - 30, width: 34, height: 7)), with: .color(Color(red: 0.95, green: 0.75, blue: 0.1)))
        let brim = Path(roundedRect: CGRect(x: headC.x - 28, y: headC.y - 24, width: 58, height: 7), cornerRadius: 3.5)
        b.fill(brim, with: .color(hatColor))
    }

    // MARK: Glass of water

    static func glassRect() -> CGRect {
        let c = contact
        return CGRect(x: c.x - 46, y: c.y - 46, width: 92, height: floorY - (c.y - 46) - 1)
    }

    static func waterY() -> CGFloat { contact.y - 9 }

    static func drawGlassBack(_ ctx: inout GraphicsContext, sincePeck: Double?, time: Double) {
        let g = glassRect()
        let shape = Path(roundedRect: g, cornerRadius: 6)
        ctx.fill(shape, with: .color(Color(red: 0.88, green: 0.95, blue: 1.0).opacity(0.55)))
        let w = waterY()
        var water = Path()
        water.move(to: CGPoint(x: g.minX + 3, y: w))
        let wobble = sincePeck.map { $0 > 0.18 && $0 < 2 ? 3 * exp(-2.5 * ($0 - 0.18)) : 0 } ?? 0
        for i in 0...20 {
            let x = g.minX + 3 + (g.width - 6) * CGFloat(i) / 20
            let y = w + CGFloat(wobble * sin(Double(i) * 1.1 - time * 14) + 0.8 * sin(Double(i) * 0.7 + time * 2))
            water.addLine(to: CGPoint(x: x, y: y))
        }
        water.addLine(to: CGPoint(x: g.maxX - 3, y: g.maxY - 3))
        water.addLine(to: CGPoint(x: g.minX + 3, y: g.maxY - 3))
        water.closeSubpath()
        ctx.fill(water, with: .color(Color(red: 0.45, green: 0.72, blue: 0.95).opacity(0.75)))
    }

    static func drawGlassFront(_ ctx: inout GraphicsContext, sincePeck: Double?) {
        let g = glassRect()
        let w = waterY()
        // Tint over the submerged beak
        ctx.fill(Path(CGRect(x: g.minX + 3, y: w + 2, width: g.width - 6, height: g.maxY - w - 5)),
                 with: .color(Color(red: 0.45, green: 0.72, blue: 0.95).opacity(0.35)))
        let shape = Path(roundedRect: g, cornerRadius: 6)
        ctx.stroke(shape, with: .color(Color(red: 0.55, green: 0.70, blue: 0.85)), lineWidth: 2.5)
        ctx.fill(Path(roundedRect: CGRect(x: g.minX + 8, y: g.minY + 8, width: 6, height: g.height - 20), cornerRadius: 3),
                 with: .color(.white.opacity(0.6)))

        // Splash droplets + ripple
        guard let e = sincePeck, e > 0.18, e < 1.0 else { return }
        let s = e - 0.18
        let c = CGPoint(x: contact.x, y: w)
        for i in 0..<7 {
            let a = (Double(i) / 6.0 - 0.5) * 2.2
            let vx = sin(a) * 70, vy = 110 + Double(i % 3) * 25
            let p = CGPoint(x: c.x + vx * s, y: c.y - vy * s + 0.5 * 600 * s * s)
            guard p.y < w + 2 else { continue }
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - 2.5, y: p.y - 3, width: 5, height: 6)),
                     with: .color(Color(red: 0.45, green: 0.72, blue: 0.95).opacity(1 - s)))
        }
        let r = 6 + 50 * s
        ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: w - r * 0.18, width: r * 2, height: r * 0.36)),
                   with: .color(.white.opacity(0.8 * (1 - s))), lineWidth: 1.5)
    }

    // MARK: Keyboard

    static func keyboardFrame() -> CGRect {
        let c = contact
        return CGRect(x: c.x - 92, y: c.y - 5, width: 122, height: floorY - (c.y - 5) - 1)
    }

    static func enterKeyRect(pressed: Bool) -> CGRect {
        let c = contact
        return CGRect(x: c.x - 16, y: c.y + (pressed ? 3 : 0), width: 36, height: 30)
    }

    static func drawKeyboard(_ ctx: inout GraphicsContext, sincePeck: Double?) {
        let k = keyboardFrame()
        let body = Path(roundedRect: k, cornerRadius: 7)
        ctx.fill(body, with: .color(Color(white: 0.78)))
        ctx.stroke(body, with: .color(Color(white: 0.5)), lineWidth: 1.5)
        let keyColor = Color(white: 0.97)
        let rowH: CGFloat = 13, gap: CGFloat = 3
        let enter = enterKeyRect(pressed: false)
        for row in 0..<3 {
            let y = k.minY + 5 + CGFloat(row) * (rowH + gap)
            let right = row < 2 ? enter.minX - gap : k.maxX - 5
            if row == 2 {
                // modifiers + space bar
                let space = CGRect(x: k.minX + 40, y: y, width: 70, height: rowH)
                ctx.fill(Path(roundedRect: space, cornerRadius: 2.5), with: .color(keyColor))
                for x in [k.minX + 5, k.minX + 22, space.maxX + gap, space.maxX + gap + 17] where x + 14 <= right {
                    ctx.fill(Path(roundedRect: CGRect(x: x, y: y, width: 14, height: rowH), cornerRadius: 2.5), with: .color(keyColor))
                }
                continue
            }
            var x = k.minX + 5 + (row == 1 ? 6 : 0)
            while x + 13 <= right {
                ctx.fill(Path(roundedRect: CGRect(x: x, y: y, width: 13, height: rowH), cornerRadius: 2.5), with: .color(keyColor))
                x += 13 + gap
            }
        }
        let pressed = isContact(sincePeck)
        let er = enterKeyRect(pressed: pressed)
        let enterPath = Path(roundedRect: er, cornerRadius: 3)
        ctx.fill(enterPath, with: .color(pressed ? Color(red: 1, green: 0.85, blue: 0.4) : keyColor))
        ctx.stroke(enterPath, with: .color(Color(white: 0.55)), lineWidth: 1)
        ctx.draw(Text("⏎").font(.system(size: 13, weight: .bold)).foregroundColor(Color(white: 0.3)),
                 at: CGPoint(x: er.midX + 6, y: er.midY + 4))
    }

    static func drawKeyFlash(_ ctx: inout GraphicsContext, sincePeck: Double?) {
        guard let e = sincePeck, e > 0.18, e < 0.7 else { return }
        let s = (e - 0.18) / 0.52
        let c = contact
        for i in 0..<6 {
            let a = Double.pi * (1.1 + 0.8 * Double(i) / 5)
            let r0 = 10 + 10 * s, r1 = 18 + 18 * s
            var p = Path()
            p.move(to: CGPoint(x: c.x + cos(a) * r0, y: c.y + sin(a) * r0))
            p.addLine(to: CGPoint(x: c.x + cos(a) * r1, y: c.y + sin(a) * r1))
            ctx.stroke(p, with: .color(Color.orange.opacity(1 - s)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        }
        ctx.draw(Text("tap!").font(.system(size: 11, weight: .heavy, design: .rounded)).foregroundColor(.orange.opacity(1 - s)),
                 at: CGPoint(x: c.x - 40, y: c.y - 30 - 10 * s))
    }
}

struct BirdScene: View {
    var target: PeckTarget
    var running: Bool
    var interval: Double
    var lastPeck: Date?

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let since = lastPeck.map { tl.date.timeIntervalSince($0) }
                BirdArt.draw(&ctx, canvas: size, time: tl.date.timeIntervalSinceReferenceDate,
                           sincePeck: since, running: running, interval: interval, target: target)
            }
        }
    }
}

// MARK: - UI

struct ContentView: View {
    @StateObject private var pecker = Pecker()

    var body: some View {
        VStack(spacing: 12) {
            BirdScene(target: pecker.target, running: pecker.running,
                      interval: pecker.interval, lastPeck: pecker.lastPeck)
                .aspectRatio(BirdArt.size.width / BirdArt.size.height, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            HStack {
                Button(action: pecker.toggle) {
                    Label(pecker.running ? "Stop" : "Start",
                          systemImage: pecker.running ? "stop.fill" : "play.fill")
                        .frame(minWidth: 80)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .tint(pecker.running ? .red : .accentColor)

                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(pecker.presses)").font(.system(size: 22, weight: .bold, design: .rounded)).monospacedDigit()
                    Text("pecks").font(.caption).foregroundStyle(.secondary)
                }
            }

            Picker("Dip into", selection: $pecker.target) {
                ForEach(PeckTarget.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Text("Key")
                    Picker("", selection: $pecker.keyMode) {
                        ForEach(KeyMode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden()
                }
                GridRow {
                    Text("Every")
                    HStack {
                        Slider(value: $pecker.interval, in: 0.5...10, step: 0.5)
                        Text(String(format: "%.1fs", pecker.interval)).monospacedDigit().frame(width: 40, alignment: .trailing)
                    }
                }
                GridRow {
                    Text("App")
                    TextField("App name", text: $pecker.targetApp).textFieldStyle(.roundedBorder)
                }
            }

            HStack(spacing: 6) {
                Circle().fill(pecker.running ? (pecker.status.hasPrefix("Peck") ? .green : .orange) : .gray)
                    .frame(width: 8, height: 8)
                Text(pecker.status).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
            }

            if !pecker.trusted {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                    Text("Allow Drinking Bird in Accessibility so it can press keys.")
                        .font(.caption)
                    Spacer()
                    Button("Open Settings", action: pecker.openAccessibilitySettings).controlSize(.small)
                }
            }
        }
        .padding(16)
        .frame(width: 400)
    }
}

// MARK: - App

@main
struct DrinkingBirdApp: App {
    init() {
        // `DrinkingBird --render-icon out.png` renders the app icon and exits (used by build.sh).
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--render-icon"), i + 1 < args.count {
            Self.renderIcon(to: args[i + 1])
            exit(0)
        }
        // `DrinkingBird --render-frame out.png <secondsSincePeck> <water|keyboard>` — debug snapshot.
        if let i = args.firstIndex(of: "--render-frame"), i + 3 < args.count {
            let since = Double(args[i + 2]) ?? 0
            let target: PeckTarget = args[i + 3] == "keyboard" ? .keyboard : .water
            let view = Canvas { ctx, size in
                BirdArt.draw(&ctx, canvas: size, time: 0, sincePeck: since, running: true, interval: 1, target: target)
            }.frame(width: 720, height: 580)
            let r = ImageRenderer(content: view)
            if let cg = r.cgImage {
                try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?
                    .write(to: URL(fileURLWithPath: args[i + 1]))
            }
            exit(0)
        }
    }

    var body: some Scene {
        WindowGroup("Drinking Bird") {
            ContentView()
        }
        .windowResizability(.contentSize)
        .windowLevel(.floating)
    }

    @MainActor
    static func renderIcon(to path: String) {
        let view = ZStack {
            RoundedRectangle(cornerRadius: 220, style: .continuous)
                .fill(Color(red: 0.93, green: 0.72, blue: 0.74))
            Canvas { ctx, size in
                // Show the bird mid-dip for a lively icon.
                BirdArt.draw(&ctx, canvas: size, time: 0, sincePeck: 0.14, running: false, interval: 1, target: .water)
            }
            .clipShape(RoundedRectangle(cornerRadius: 220, style: .continuous))
        }
        .frame(width: 1024, height: 1024)
        let r = ImageRenderer(content: view)
        r.scale = 1
        guard let cg = r.cgImage else { return }
        let rep = NSBitmapImageRep(cgImage: cg)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
