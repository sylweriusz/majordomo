import AppKit

enum WaveformOverlayMode {
    case recording
    case transcribing
}

/// Number of amplitude bars in the waveform indicator. Single source of truth
/// shared by the view and the overlay controller's level buffers.
enum WaveformLevels {
    static let count = 64
}

@MainActor
final class WaveformOverlayView: NSView {
    private var timer: Timer?
    private var animating = false
    var visualStyle: IndicatorVisualStyle = .defaultStyle {
        didSet { needsDisplay = true }
    }
    var colorPalette: IndicatorColorPalette = .defaultPalette {
        didSet { needsDisplay = true }
    }
    var isHorizontallyMirrored = false {
        didSet { needsDisplay = true }
    }
    private var mode: WaveformOverlayMode = .recording
    private var phase: Float = 0
    private var levels: [Float] = Array(repeating: 0, count: WaveformLevels.count)
    private let levelCount = WaveformLevels.count

    private var latestLevels: [Float] = Array(repeating: 0, count: WaveformLevels.count)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.cornerCurve = .continuous
        layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.92).cgColor
        layer?.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    isolated deinit {
        // Safety net: the 45fps run-loop timer retains its schedule until
        // invalidated. Callers pair start/stopAnimating, but if a view is torn
        // down without a stop, this prevents a leaked, forever-firing timer.
        // `isolated` so the main-actor `timer` property is reachable here.
        timer?.invalidate()
    }

    func startAnimating(mode: WaveformOverlayMode = .recording) {
        animating = true
        self.mode = mode
        phase = 0
        levels = Array(repeating: 0, count: levelCount)
        latestLevels = Array(repeating: 0, count: levelCount)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 45.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stopAnimating() {
        animating = false
        timer?.invalidate()
        timer = nil
    }

    func setLevels(_ newLevels: [Float]) {
        guard newLevels.count == levelCount else { return }
        latestLevels = newLevels
    }

    private func tick() {
        guard animating else { return }

        phase += mode == .recording ? 0.075 : 0.12

        switch mode {
        case .recording:
            for i in 0..<levelCount {
                let x = Float(i) / Float(levelCount - 1)
                let idle = 0.018 + 0.025 * (0.5 + 0.5 * sin(phase * 1.7 + x * 12))
                let target = max(latestLevels[i], idle)
                let blend: Float = target > levels[i] ? 0.58 : 0.18
                levels[i] = levels[i] * (1 - blend) + min(1, target) * blend
            }
        case .transcribing:
            for i in 0..<levelCount {
                let x = Float(i) / Float(levelCount - 1)
                let centerBoost = 1 - min(1, abs(x - 0.5) * 2)
                let wave = 0.5 + 0.5 * sin(phase + x * 18)
                let shimmer = 0.5 + 0.5 * sin(phase * 2.7 + x * 47)
                let carrier = 0.5 + 0.5 * sin(phase * 0.58 - x * 10)
                let noise = Float.random(in: 0...0.13)
                let target = 0.08 + wave * 0.16 + shimmer * 0.12 + carrier * 0.08 + noise + centerBoost * 0.32
                levels[i] = levels[i] * 0.62 + min(1, target) * 0.38
            }
        }

        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let drawRect = bounds.insetBy(dx: 10, dy: 6)

        context.saveGState()
        defer { context.restoreGState() }

        if isHorizontallyMirrored {
            context.translateBy(x: bounds.minX + bounds.maxX, y: 0)
            context.scaleBy(x: -1, y: 1)
        }

        drawInteriorGlass(in: bounds, context: context)

        switch visualStyle {
        case .signalGlass:
            drawSignalGlass(in: drawRect, context: context)
        case .liquidNeon:
            drawLiquidNeon(in: drawRect, context: context)
        case .auroraPlasma:
            drawAuroraPlasma(in: drawRect, context: context)
        case .nebulaEngine:
            drawNebulaEngine(in: drawRect, context: context)
        case .temporalRift:
            drawTemporalRift(in: drawRect, context: context)
        case .crystalLens:
            drawCrystalLens(in: drawRect, context: context)
        case .cosmicStorm:
            drawCosmicStorm(in: drawRect, context: context)
        case .neuralNetwork:
            drawNeuralNetwork(in: drawRect, context: context)
        case .plasmaVortex:
            drawPlasmaVortex(in: drawRect, context: context)
        case .ufoReactor:
            drawUFOReactor(in: drawRect, context: context)
        case .xenoLattice:
            drawXenoLattice(in: drawRect, context: context)
        case .unicornSparklepop:
            drawUnicornSparklepop(in: drawRect, context: context)
        }
    }

    private func drawInteriorGlass(in rect: NSRect, context: CGContext) {
        drawLinearGradient(
            in: rect,
            context: context,
            colors: [
                NSColor.white.withAlphaComponent(0.09),
                NSColor.black.withAlphaComponent(0.0),
                NSColor.black.withAlphaComponent(0.34)
            ],
            locations: [0, 0.42, 1],
            start: CGPoint(x: rect.midX, y: rect.maxY),
            end: CGPoint(x: rect.midX, y: rect.minY)
        )

        context.saveGState()
        context.setBlendMode(.plusLighter)
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.08).cgColor)
        context.setLineWidth(1)
        let upper = rect.insetBy(dx: 8, dy: 6)
        context.move(to: CGPoint(x: upper.minX, y: upper.maxY))
        context.addLine(to: CGPoint(x: upper.maxX, y: upper.maxY))
        context.strokePath()
        context.restoreGState()
    }

    private func drawSignalGlass(in rect: NSRect, context: CGContext) {
        let colors = activePaletteColors()
        let primary = colors.mid
        let path = makeEnvelopePath(in: rect, amplitude: 0.78, minimumHeight: 1.6, phaseOffset: 0)

        stroke(path, context: context, color: primary.withAlphaComponent(0.30), width: 7.0, blur: 9)
        stroke(path, context: context, color: primary.withAlphaComponent(0.86), width: 1.65, blur: 4)
        drawCenterFilament(in: rect, context: context, color: primary.withAlphaComponent(0.62), width: 1.2)
        drawMicroTicks(in: rect, context: context, color: primary.withAlphaComponent(0.30), density: 12, heightScale: 0.35)
        if mode == .transcribing {
            drawPrismScanner(in: rect, context: context, color: primary, spark: colors.spark)
        } else {
            drawSignalGlassListeningSweep(in: rect, context: context, color: primary, spark: colors.spark)
        }
    }

    private func drawLiquidNeon(in rect: NSRect, context: CGContext) {
        let colors = activePaletteColors()
        let left = colors.low
        let middle = colors.mid
        let right = colors.high
        let path = makeEnvelopePath(in: rect, amplitude: 1.0, minimumHeight: 2.2, phaseOffset: 0)
        let echoPath = makeEnvelopePath(in: rect.insetBy(dx: 4, dy: 2), amplitude: 0.62, minimumHeight: 1.2, phaseOffset: 1.7)

        fill(path, context: context, colors: [left.withAlphaComponent(0.28), middle.withAlphaComponent(0.42), right.withAlphaComponent(0.28)])
        stroke(echoPath, context: context, color: middle.withAlphaComponent(0.14), width: 8, blur: 12)
        stroke(path, context: context, color: middle.withAlphaComponent(0.52), width: 2.2, blur: 9)
        stroke(path, context: context, color: NSColor.white.withAlphaComponent(0.38), width: 0.72, blur: 2)
        drawCenterFilament(in: rect, context: context, color: middle.withAlphaComponent(0.42), width: 1.0)
        if mode == .transcribing {
            drawNeonComet(in: rect, context: context, colors: colors)
        } else {
            drawLiquidListeningGlints(in: rect, context: context, colors: colors)
        }
        drawParticles(in: rect, context: context, color: middle.withAlphaComponent(0.75), threshold: 0.58, count: 13)
    }

    private func drawAuroraPlasma(in rect: NSRect, context: CGContext) {
        let colors = activePaletteColors()
        let colorShift = [colors.low, colors.mid, colors.high]

        for layer in 0..<3 {
            let inset = CGFloat(layer) * 3.0
            let amplitude = 1.03 - CGFloat(layer) * 0.20
            let layerPath = makeEnvelopePath(in: rect.insetBy(dx: inset, dy: inset * 0.55), amplitude: amplitude, minimumHeight: 1.6, phaseOffset: Float(layer) * 1.25)
            fill(layerPath, context: context, colors: colorShift.map { $0.withAlphaComponent(0.34 - CGFloat(layer) * 0.07) })
            stroke(layerPath, context: context, color: colorShift[layer].withAlphaComponent(0.42), width: 4.0 - CGFloat(layer) * 0.7, blur: 10 + CGFloat(layer) * 4)
        }

        drawInterferenceLines(in: rect, context: context, colors: colorShift)
        if mode == .transcribing {
            drawAuroraThrob(in: rect, context: context, colors: colors)
        } else {
            drawAuroraListeningCurtain(in: rect, context: context, colors: colors)
        }
        drawParticles(in: rect, context: context, color: colors.spark.withAlphaComponent(0.76), threshold: 0.50, count: 18)
    }

    private func drawUFOReactor(in rect: NSRect, context: CGContext) {
        let colors = activePaletteColors()
        let deepBlue = colors.low
        let modeAccent = colors.mid
        let violet = colors.high
        let whiteHot = colors.spark

        let outerPath = makeEnvelopePath(in: rect, amplitude: 1.12, minimumHeight: 2.0, phaseOffset: 0.0)
        let innerPath = makeEnvelopePath(in: rect.insetBy(dx: 9, dy: 4), amplitude: 0.62, minimumHeight: 1.2, phaseOffset: 2.4)

        stroke(outerPath, context: context, color: modeAccent.withAlphaComponent(0.34), width: 11.5, blur: 18)
        fill(outerPath, context: context, colors: [deepBlue.withAlphaComponent(0.74), modeAccent.withAlphaComponent(0.92), violet.withAlphaComponent(0.74)])
        fill(innerPath, context: context, colors: [NSColor.black.withAlphaComponent(0.12), whiteHot.withAlphaComponent(0.36), NSColor.black.withAlphaComponent(0.10)])
        stroke(outerPath, context: context, color: whiteHot.withAlphaComponent(0.68), width: 0.9, blur: 3)

        drawOriginalUFOReactorCore(in: rect, context: context, color: modeAccent)
        drawInterferenceLines(in: rect, context: context, colors: [deepBlue, modeAccent, violet])
        drawOriginalUFOParticles(in: rect, context: context, color: whiteHot.withAlphaComponent(0.90), threshold: 0.42, count: 24)
        drawScanBloom(in: rect, context: context, color: modeAccent.withAlphaComponent(0.32), width: 76)
    }

    private func drawNebulaEngine(in rect: NSRect, context: CGContext) {
        let colors = activePaletteColors()
        let energy = averageLevel()
        let fieldRect = rect.insetBy(dx: -12, dy: -8)
        let stabilized = mode == .transcribing

        context.saveGState()
        context.setBlendMode(.plusLighter)
        context.clip(to: fieldRect)

        drawNebulaMist(in: fieldRect, context: context, colors: colors, energy: energy, stabilized: stabilized)
        drawNebulaAccretionField(in: rect, context: context, colors: colors, energy: energy, stabilized: stabilized)
        drawNebulaFilaments(in: rect, context: context, colors: colors, stabilized: stabilized)
        if stabilized {
            drawNebulaStabilizedCore(in: rect, context: context, colors: colors, energy: energy)
            drawNebulaMicroFlares(in: rect, context: context, colors: colors, threshold: 0.60, count: 14, stabilized: true)
        } else {
            drawNebulaLivingCore(in: rect, context: context, colors: colors, energy: energy)
            drawNebulaMicroFlares(in: rect, context: context, colors: colors, threshold: 0.34, count: 24, stabilized: false)
        }

        context.restoreGState()
    }

    private func drawNebulaMist(in rect: NSRect, context: CGContext, colors: IndicatorPaletteColors, energy: CGFloat, stabilized: Bool) {
        let palette = [colors.low, colors.mid, colors.high, colors.spark]
        for layer in 0..<4 {
            let layerPhase = phase * (0.23 + Float(layer) * 0.06) + Float(layer) * 1.31
            let drift = CGFloat(sin(layerPhase)) * rect.width * (stabilized ? 0.025 : 0.055)
            let lift = CGFloat(cos(layerPhase * 1.37)) * rect.height * (0.06 + energy * 0.10)
            let width = rect.width * (0.30 + CGFloat(layer) * 0.14 + energy * 0.12)
            let height = rect.height * (0.72 + CGFloat(layer) * 0.16 + energy * 0.24)
            let t = CGFloat(layer) / 3
            let centerX = rect.minX + rect.width * (0.22 + t * 0.56) + drift
            let centerY = rect.midY + lift
            let blobRect = NSRect(x: centerX - width * 0.5, y: centerY - height * 0.5, width: width, height: height)
            let pulse = CGFloat(0.5 + 0.5 * sin(phase * (0.52 + Float(layer) * 0.11) + Float(layer)))
            let alpha = (stabilized ? 0.08 : 0.13) + energy * 0.10 + pulse * 0.05
            let color = palette[layer]

            context.saveGState()
            context.addEllipse(in: blobRect)
            context.clip()
            drawRadialGradient(
                in: blobRect,
                context: context,
                colors: [color.withAlphaComponent(alpha), colors.mid.withAlphaComponent(alpha * 0.48), color.withAlphaComponent(0)],
                locations: [0, 0.42, 1],
                center: CGPoint(x: blobRect.midX + drift * 0.18, y: blobRect.midY)
            )
            context.restoreGState()
        }
    }

    private func drawNebulaAccretionField(in rect: NSRect, context: CGContext, colors: IndicatorPaletteColors, energy: CGFloat, stabilized: Bool) {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let pulse = CGFloat(0.5 + 0.5 * sin(phase * 1.18))
        let loopCount = stabilized ? 5 : 4

        context.saveGState()
        context.setBlendMode(.plusLighter)
        context.setLineCap(.round)

        for loop in 0..<loopCount {
            let progress = CGFloat(loop) / CGFloat(max(1, loopCount - 1))
            let audio = mirroredLevel(at: min(levelCount - 1, 10 + loop * 11))
            let radiusX = rect.height * (0.72 + progress * 0.74 + energy * 0.42 + audio * 0.32)
            let radiusY = radiusX * (0.24 + progress * 0.07 + pulse * 0.04)
            let orbitRect = NSRect(x: center.x - radiusX, y: center.y - radiusY, width: radiusX * 2, height: radiusY * 2)
            let alpha = (stabilized ? 0.08 : 0.10) + energy * 0.12 + audio * 0.16 - progress * 0.025
            let color = [colors.low, colors.mid, colors.high, colors.spark][loop % 4]

            context.setShadow(offset: .zero, blur: 18 + audio * 18, color: color.withAlphaComponent(alpha).cgColor)
            context.setStrokeColor(color.withAlphaComponent(alpha * 0.72).cgColor)
            context.setLineWidth(0.65 + progress * 0.38 + audio * 0.55)
            context.strokeEllipse(in: orbitRect)
        }

        let shearCount = stabilized ? 4 : 6
        for shear in 0..<shearCount {
            let side: CGFloat = shear.isMultiple(of: 2) ? 1 : -1
            let t = CGFloat(shear) / CGFloat(max(1, shearCount - 1))
            let audio = mirroredLevel(at: Int(t * CGFloat(levelCount - 1)))
            let xOffset = side * rect.width * (0.12 + t * 0.22)
            let yOffset = CGFloat(sin(phase * 0.74 + Float(shear))) * rect.height * (0.10 + audio * 0.16)
            let controlLift = side * rect.height * (0.16 + audio * 0.24)
            let color = shear.isMultiple(of: 2) ? colors.spark : colors.high
            let alpha = (stabilized ? 0.06 : 0.10) + audio * 0.18 + energy * 0.06

            context.setShadow(offset: .zero, blur: 12 + audio * 16, color: color.withAlphaComponent(alpha).cgColor)
            context.setStrokeColor(color.withAlphaComponent(alpha).cgColor)
            context.setLineWidth(0.55 + audio * 0.75)
            context.beginPath()
            context.move(to: CGPoint(x: center.x - xOffset, y: center.y - yOffset))
            context.addCurve(
                to: CGPoint(x: center.x + xOffset, y: center.y + yOffset),
                control1: CGPoint(x: center.x - xOffset * 0.45, y: center.y + controlLift),
                control2: CGPoint(x: center.x + xOffset * 0.45, y: center.y - controlLift)
            )
            context.strokePath()
        }

        context.restoreGState()
    }

    private func drawNebulaFilaments(in rect: NSRect, context: CGContext, colors: IndicatorPaletteColors, stabilized: Bool) {
        let palette = [colors.low, colors.mid, colors.high, colors.spark]
        let filamentCount = 17
        let center = CGPoint(x: rect.midX, y: rect.midY)

        context.saveGState()
        context.setLineCap(.round)
        context.setLineJoin(.round)

        for index in 0..<filamentCount {
            let t = CGFloat(index) / CGFloat(filamentCount - 1)
            let audio = mirroredLevel(at: Int(t * CGFloat(levelCount - 1)))
            let sidePull = (t - 0.5) * 2
            let sway = CGFloat(sin(phase * (1.16 + Float(index) * 0.05) + Float(index) * 0.73))
            let counter = CGFloat(cos(phase * (0.72 + Float(index) * 0.035) - Float(index) * 1.11))
            let reach = stabilized ? (0.42 + audio * 0.18) : (0.62 + audio * 0.50)
            let endX = center.x + sidePull * rect.width * reach * 0.5
            let endY = center.y + (sway + counter * 0.35) * rect.height * (0.18 + audio * (stabilized ? 0.16 : 0.42))
            let controlBend = CGFloat(cos(phase * 0.74 + Float(index) * 1.17)) * rect.height * (0.18 + audio * 0.26)
            let control1 = CGPoint(x: center.x + (endX - center.x) * 0.22, y: center.y - controlBend)
            let control2 = CGPoint(x: center.x + (endX - center.x) * 0.78, y: endY + controlBend)
            let alpha = stabilized ? (0.10 + audio * 0.16) : (0.16 + audio * 0.40)
            let lineWidth = stabilized ? (0.56 + audio * 0.75) : (0.75 + audio * 1.55)
            let color = palette[index % palette.count]

            context.setShadow(offset: .zero, blur: 13 + audio * 20, color: color.withAlphaComponent(alpha).cgColor)
            context.setStrokeColor(color.withAlphaComponent(alpha * 0.42).cgColor)
            context.setLineWidth(lineWidth * 2.6)
            context.beginPath()
            context.move(to: center)
            context.addCurve(to: CGPoint(x: endX, y: endY), control1: control1, control2: control2)
            context.strokePath()

            context.setShadow(offset: .zero, blur: 5 + audio * 10, color: colors.spark.withAlphaComponent(alpha * 0.65).cgColor)
            context.setStrokeColor(color.withAlphaComponent(alpha).cgColor)
            context.setLineWidth(lineWidth)
            context.beginPath()
            context.move(to: center)
            context.addCurve(to: CGPoint(x: endX, y: endY), control1: control1, control2: control2)
            context.strokePath()
        }

        context.restoreGState()
    }

    private func drawNebulaLivingCore(in rect: NSRect, context: CGContext, colors: IndicatorPaletteColors, energy: CGFloat) {
        let pulse = CGFloat(0.5 + 0.5 * sin(phase * 1.46 + sin(phase * 0.41)))
        let wobbleX = CGFloat(sin(phase * 0.82)) * (1.1 + energy * 2.6)
        let wobbleY = CGFloat(cos(phase * 0.67)) * (0.7 + energy * 1.8)
        let radiusX = rect.height * (0.78 + energy * 0.50 + pulse * 0.18)
        let radiusY = rect.height * (0.26 + energy * 0.22 + pulse * 0.08)
        let coreRect = NSRect(x: rect.midX + wobbleX - radiusX, y: rect.midY + wobbleY - radiusY, width: radiusX * 2, height: radiusY * 2)

        context.saveGState()
        context.setShadow(offset: .zero, blur: 22 + energy * 24, color: colors.mid.withAlphaComponent(0.42 + energy * 0.26).cgColor)
        context.addEllipse(in: coreRect)
        context.clip()
        drawRadialGradient(
            in: coreRect,
            context: context,
            colors: [colors.spark.withAlphaComponent(0.46), colors.mid.withAlphaComponent(0.34), colors.low.withAlphaComponent(0.05), colors.high.withAlphaComponent(0)],
            locations: [0, 0.20, 0.60, 1],
            center: CGPoint(x: coreRect.midX + wobbleX * 0.35, y: coreRect.midY)
        )
        context.restoreGState()

        context.saveGState()
        context.setBlendMode(.plusLighter)
        for ring in 0..<3 {
            let ringScale = 1 + CGFloat(ring) * 0.36 + pulse * 0.10
            let ringRect = coreRect.insetBy(dx: -radiusX * 0.18 * ringScale, dy: -radiusY * 0.22 * ringScale)
            context.setStrokeColor((ring == 0 ? colors.spark : colors.mid).withAlphaComponent(0.18 - CGFloat(ring) * 0.035 + energy * 0.08).cgColor)
            context.setLineWidth(0.7 + CGFloat(ring) * 0.22)
            context.setShadow(offset: .zero, blur: 9 + CGFloat(ring) * 6, color: colors.high.withAlphaComponent(0.18 + energy * 0.14).cgColor)
            context.strokeEllipse(in: ringRect)
        }
        let lensRect = NSRect(x: rect.midX - rect.width * 0.22, y: rect.midY - 1.2, width: rect.width * 0.44, height: 2.4)
        drawLinearGradient(
            in: lensRect,
            context: context,
            colors: [colors.low.withAlphaComponent(0), colors.spark.withAlphaComponent(0.24 + energy * 0.18), colors.high.withAlphaComponent(0)],
            locations: [0, 0.5, 1],
            start: CGPoint(x: lensRect.minX, y: lensRect.midY),
            end: CGPoint(x: lensRect.maxX, y: lensRect.midY)
        )
        context.restoreGState()
    }

    private func drawNebulaStabilizedCore(in rect: NSRect, context: CGContext, colors: IndicatorPaletteColors, energy: CGFloat) {
        let lock = CGFloat(0.5 + 0.5 * sin(phase * 0.36))
        let radiusX = rect.height * (1.05 + lock * 0.08 + energy * 0.12)
        let radiusY = rect.height * (0.34 + lock * 0.03 + energy * 0.05)
        let coreRect = NSRect(x: rect.midX - radiusX, y: rect.midY - radiusY, width: radiusX * 2, height: radiusY * 2)

        context.saveGState()
        context.setShadow(offset: .zero, blur: 24, color: colors.mid.withAlphaComponent(0.40).cgColor)
        context.addEllipse(in: coreRect)
        context.clip()
        drawRadialGradient(
            in: coreRect,
            context: context,
            colors: [colors.spark.withAlphaComponent(0.38), colors.mid.withAlphaComponent(0.24), colors.high.withAlphaComponent(0.10), colors.low.withAlphaComponent(0)],
            locations: [0, 0.26, 0.58, 1],
            center: CGPoint(x: coreRect.midX, y: coreRect.midY)
        )
        context.restoreGState()

        context.saveGState()
        context.setBlendMode(.plusLighter)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        for ring in 0..<4 {
            let progress = CGFloat(ring) / 3
            let ringRect = coreRect.insetBy(dx: -radiusX * progress * 0.40, dy: -radiusY * progress * 0.55)
            let alpha = 0.18 - progress * 0.05 + lock * 0.035
            context.setStrokeColor((ring.isMultiple(of: 2) ? colors.spark : colors.mid).withAlphaComponent(alpha).cgColor)
            context.setLineWidth(0.55 + progress * 0.28)
            context.setShadow(offset: .zero, blur: 8 + progress * 10, color: colors.mid.withAlphaComponent(alpha).cgColor)
            context.strokeEllipse(in: ringRect)
        }

        for beam in 0..<5 {
            let offset = (CGFloat(beam) - 2) * rect.width * 0.08
            let beamRect = NSRect(x: rect.midX + offset - 0.55, y: rect.minY - 4, width: 1.1, height: rect.height + 8)
            drawLinearGradient(
                in: beamRect,
                context: context,
                colors: [colors.low.withAlphaComponent(0), colors.spark.withAlphaComponent(0.10 + lock * 0.07), colors.high.withAlphaComponent(0)],
                locations: [0, 0.5, 1],
                start: CGPoint(x: beamRect.midX, y: beamRect.maxY),
                end: CGPoint(x: beamRect.midX, y: beamRect.minY)
            )
        }
        context.restoreGState()
    }

    private func drawNebulaMicroFlares(in rect: NSRect, context: CGContext, colors: IndicatorPaletteColors, threshold: CGFloat, count: Int, stabilized: Bool) {
        guard count > 0 else { return }
        let palette = [colors.spark, colors.high, colors.mid]

        context.saveGState()
        context.setBlendMode(.plusLighter)
        context.setLineCap(.round)

        for index in 0..<count {
            let seed = Float(index) * 1.713
            let t = CGFloat((sin(phase * 0.31 + seed) + 1) * 0.5)
            let sample = Int(t * CGFloat(levelCount - 1))
            let audio = mirroredLevel(at: sample)
            let burst = max(0, (audio - threshold) / max(0.001, 1 - threshold))
            let twinkle = CGFloat(pow(Double(max(0, sin(phase * 2.2 + seed))), stabilized ? 3.6 : 2.2))
            let alpha = min(0.78, (stabilized ? 0.07 : 0.12) + burst * 0.58 + twinkle * 0.18)
            guard alpha > 0.08 else { continue }

            let orbit = CGFloat(sin(phase * 0.54 + seed * 0.7))
            let x = rect.minX + rect.width * t
            let y = rect.midY + orbit * rect.height * (stabilized ? 0.18 : 0.34) + CGFloat(cos(seed)) * 1.8
            let arm = 0.65 + burst * (stabilized ? 1.3 : 2.6) + twinkle * 1.2
            let color = palette[index % palette.count]

            context.setShadow(offset: .zero, blur: 5 + arm * 2.4, color: color.withAlphaComponent(alpha).cgColor)
            context.setStrokeColor(color.withAlphaComponent(alpha).cgColor)
            context.setLineWidth(0.42 + burst * 0.35)
            context.move(to: CGPoint(x: x - arm, y: y))
            context.addLine(to: CGPoint(x: x + arm, y: y))
            context.move(to: CGPoint(x: x, y: y - arm * 0.72))
            context.addLine(to: CGPoint(x: x, y: y + arm * 0.72))
            if !stabilized && index.isMultiple(of: 3) {
                let diagonal = arm * 0.62
                context.move(to: CGPoint(x: x - diagonal, y: y - diagonal))
                context.addLine(to: CGPoint(x: x + diagonal, y: y + diagonal))
                context.move(to: CGPoint(x: x + diagonal, y: y - diagonal))
                context.addLine(to: CGPoint(x: x - diagonal, y: y + diagonal))
            }
            context.strokePath()
        }

        context.restoreGState()
    }

    // MARK: - Temporal Rift (lightweight)

    private func drawTemporalRift(in rect: NSRect, context: CGContext) {
        let colors = activePaletteColors()
        let energy = averageLevel()
        let stabilized = mode == .transcribing
        let opening = stabilized ? min(1, 0.5 + energy * 0.3) : min(1, 0.15 + energy * 1.2)
        let fieldRect = rect.insetBy(dx: -12, dy: -8)

        context.saveGState()
        context.clip(to: fieldRect)

        drawTemporalRiftBackground(in: fieldRect, context: context, colors: colors, opening: opening, stabilized: stabilized)
        drawTemporalRiftEnvelope(in: rect, context: context, colors: colors, opening: opening, stabilized: stabilized)
        drawTemporalRiftBars(in: rect, context: context, colors: colors, opening: opening, stabilized: stabilized)
        drawTemporalRiftArcs(in: rect, context: context, colors: colors, opening: opening, stabilized: stabilized)
        drawTemporalRiftBloom(in: rect, context: context, colors: colors, opening: opening, stabilized: stabilized)
        drawTemporalRiftParticles(in: rect, context: context, colors: colors, opening: opening, stabilized: stabilized)

        if stabilized {
            drawTemporalRiftContainment(in: rect, context: context, colors: colors, opening: opening)
        } else {
            drawScanBloom(in: rect, context: context, color: colors.mid.withAlphaComponent(0.32), width: 76)
        }
        drawTemporalRiftHaze(in: rect, context: context, colors: colors, opening: opening, stabilized: stabilized)

        context.restoreGState()
    }

    private func drawTemporalRiftBackground(in rect: NSRect, context: CGContext, colors: IndicatorPaletteColors, opening: CGFloat, stabilized: Bool) {
        let center = CGPoint(x: rect.midX, y: rect.midY)

        context.saveGState()
        context.setBlendMode(.normal)
        context.setFillColor(NSColor.black.withAlphaComponent(stabilized ? 0.42 : 0.66).cgColor)
        context.fill(rect)
        context.restoreGState()

        let width = rect.width * (0.36 + opening * 0.36)
        let height = rect.height * (0.82 + opening * 0.50)
        let portalRect = NSRect(x: center.x - width * 0.5, y: center.y - height * 0.5, width: width, height: height)

        context.saveGState()
        context.setBlendMode(.plusLighter)
        context.addEllipse(in: portalRect)
        context.clip()
        drawRadialGradient(
            in: portalRect,
            context: context,
            colors: [
                colors.spark.withAlphaComponent(stabilized ? 0.18 : 0.10 + opening * 0.20),
                colors.mid.withAlphaComponent(stabilized ? 0.18 : opening * 0.22),
                colors.low.withAlphaComponent(0.04 + opening * 0.10),
                NSColor.black.withAlphaComponent(0)
            ],
            locations: [0, 0.22, 0.58, 1],
            center: CGPoint(x: center.x + CGFloat(sin(phase * 0.42)) * 2.0, y: center.y)
        )
        context.restoreGState()

        context.saveGState()
        context.setBlendMode(.normal)
        drawLinearGradient(
            in: rect,
            context: context,
            colors: [NSColor.black.withAlphaComponent(0.52), NSColor.black.withAlphaComponent(0), NSColor.black.withAlphaComponent(0.52)],
            locations: [0, 0.5, 1],
            start: CGPoint(x: rect.minX, y: rect.midY),
            end: CGPoint(x: rect.maxX, y: rect.midY)
        )
        context.restoreGState()
    }

    private func drawTemporalRiftEnvelope(in rect: NSRect, context: CGContext, colors: IndicatorPaletteColors, opening: CGFloat, stabilized: Bool) {
        let path = makeEnvelopePath(in: rect, amplitude: 0.78, minimumHeight: 1.6, phaseOffset: 0)
        let deepPath = makeEnvelopePath(in: rect.insetBy(dx: 4, dy: 2), amplitude: 0.62, minimumHeight: 1.2, phaseOffset: 1.7)

        stroke(path, context: context, color: colors.mid.withAlphaComponent(0.30 + opening * 0.20), width: 9.0, blur: 14)
        stroke(deepPath, context: context, color: colors.low.withAlphaComponent(0.14 + opening * 0.10), width: 6, blur: 10)
        fill(path, context: context, colors: [colors.low.withAlphaComponent(0.42), colors.mid.withAlphaComponent(0.56), colors.high.withAlphaComponent(0.42)])
        stroke(path, context: context, color: colors.spark.withAlphaComponent(0.58 + opening * 0.18), width: 1.2, blur: 4)
        drawCenterFilament(in: rect, context: context, color: colors.mid.withAlphaComponent(0.36), width: 1.0)
    }

    private func drawTemporalRiftBars(in rect: NSRect, context: CGContext, colors: IndicatorPaletteColors, opening: CGFloat, stabilized: Bool) {
        let barCount = 7
        let sweep = CGFloat(0.5 + 0.5 * sin(phase * 0.42))

        for i in 0..<barCount {
            let t = CGFloat(i) / CGFloat(barCount - 1)
            let audio = mirroredLevel(at: Int(t * CGFloat(levelCount - 1)))
            let barPhase = phase * (stabilized ? 0.18 : 0.62) + Float(i) * 0.73
            let x = rect.minX + rect.width * (CGFloat(i) / CGFloat(barCount - 1)) * (0.40 + sweep * 0.30)
            let width: CGFloat = 3.5 + audio * 5.0 + CGFloat(i % 3) * 0.6
            let height = rect.height * (0.40 + audio * 0.50 + CGFloat(i % 2) * 0.08)
            let y = rect.midY + CGFloat(sin(barPhase * 0.73)) * rect.height * 0.12
            let alpha = 0.12 + audio * 0.28 + opening * 0.10
            let color = i % 2 == 0 ? colors.mid : colors.high

            let barRect = NSRect(x: x - width * 0.5, y: y - height * 0.5, width: width, height: height)

            context.saveGState()
            context.setBlendMode(.plusLighter)
            context.setShadow(offset: .zero, blur: 11 + audio * 10, color: color.withAlphaComponent(alpha * 0.72).cgColor)
            drawLinearGradient(
                in: barRect,
                context: context,
                colors: [colors.low.withAlphaComponent(0), color.withAlphaComponent(alpha), colors.high.withAlphaComponent(0)],
                locations: [0, 0.5, 1],
                start: CGPoint(x: barRect.minX, y: barRect.midY),
                end: CGPoint(x: barRect.maxX, y: barRect.midY)
            )
            context.restoreGState()

            if !stabilized && audio > 0.15 {
                context.saveGState()
                context.setBlendMode(.plusLighter)
                context.setShadow(offset: .zero, blur: 14 + audio * 10, color: colors.spark.withAlphaComponent(alpha * 0.52).cgColor)
                context.setStrokeColor(colors.spark.withAlphaComponent(alpha * 0.72).cgColor)
                context.setLineWidth(0.5 + audio * 0.45)
                context.move(to: CGPoint(x: barRect.minX, y: barRect.midY))
                context.addLine(to: CGPoint(x: barRect.maxX, y: barRect.midY))
                context.strokePath()
                context.restoreGState()
            }
        }
    }

    private func drawTemporalRiftArcs(in rect: NSRect, context: CGContext, colors: IndicatorPaletteColors, opening: CGFloat, stabilized: Bool) {
        let center = CGPoint(x: rect.midX, y: rect.midY)

        for i in 0..<5 {
            let progress = CGFloat(i) / 4
            let radiusX = rect.height * (0.62 + progress * 0.62 + opening * 0.36)
            let radiusY = radiusX * (0.28 + progress * 0.08)
            let arc = CGFloat.pi * (stabilized ? 1.8 : 0.52 + opening * 0.88)
            let rotation = CGFloat(phase) * (stabilized ? 0.18 : 0.62) + CGFloat(i) * 0.54
            let color = [colors.low, colors.mid, colors.high, colors.spark, colors.low][i]
            let alpha = 0.065 + opening * 0.060 - progress * 0.012

            context.saveGState()
            context.setBlendMode(.plusLighter)
            context.setLineCap(.round)
            context.setLineDash(phase: CGFloat(i) * 3.0 + CGFloat(phase), lengths: [3.0 + progress * 4.0, 4.5 + progress * 3.0])
            context.setShadow(offset: .zero, blur: 13 + progress * 10, color: color.withAlphaComponent(alpha).cgColor)
            context.setStrokeColor(color.withAlphaComponent(alpha).cgColor)
            context.setLineWidth(0.85 + progress * 0.34)
            strokeTemporalArc(center: center, radiusX: radiusX, radiusY: radiusY, start: rotation, end: rotation + arc, context: context)
            context.restoreGState()
        }
    }

    private func drawTemporalRiftBloom(in rect: NSRect, context: CGContext, colors: IndicatorPaletteColors, opening: CGFloat, stabilized: Bool) {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let pulse = CGFloat(0.5 + 0.5 * sin(phase * 0.92))
        let width = rect.width * (0.36 + pulse * 0.18 + opening * 0.28)
        let height = rect.height * (1.10 + opening * 0.42)
        let bloomRect = NSRect(x: center.x - width * 0.5, y: center.y - height * 0.5, width: width, height: height)

        context.saveGState()
        context.setBlendMode(.plusLighter)
        context.addEllipse(in: bloomRect)
        context.clip()
        drawRadialGradient(
            in: bloomRect,
            context: context,
            colors: [colors.spark.withAlphaComponent(0.16 + opening * 0.14), colors.mid.withAlphaComponent(0.12), colors.low.withAlphaComponent(0), NSColor.black.withAlphaComponent(0)],
            locations: [0, 0.28, 0.60, 1],
            center: CGPoint(x: center.x, y: center.y)
        )
        context.restoreGState()
    }

    private func drawTemporalRiftParticles(in rect: NSRect, context: CGContext, colors: IndicatorPaletteColors, opening: CGFloat, stabilized: Bool) {
        let particleCount = 18
        let palette = [colors.spark, colors.high, colors.mid, colors.low]

        context.saveGState()
        context.setBlendMode(.plusLighter)
        context.setLineCap(.round)

        for i in 0..<particleCount {
            let seed = Float(i) * 1.71
            let t = CGFloat((sin(phase * 0.42 + seed) + 1) * 0.5)
            let audio = mirroredLevel(at: Int(t * CGFloat(levelCount - 1)))
            let burst = max(0, audio - 0.34) / 0.66
            let alpha = min(0.78, opening * 0.12 + burst * 0.56 + CGFloat(pow(Double(max(0, sin(phase * 2.4 + seed))), 2.0)) * 0.16)
            guard alpha > 0.08 else { continue }

            let x = rect.minX + rect.width * t
            let y = rect.midY + CGFloat(cos(phase * 0.7 + seed)) * rect.height * (0.16 + audio * 0.32)
            let arm = 0.65 + burst * 2.9 + opening * 1.2
            let color = palette[i % palette.count]

            context.setShadow(offset: .zero, blur: 5 + arm * 2.8, color: color.withAlphaComponent(alpha).cgColor)
            context.setStrokeColor(color.withAlphaComponent(alpha).cgColor)
            context.setLineWidth(0.42 + burst * 0.36)
            context.move(to: CGPoint(x: x - arm, y: y))
            context.addLine(to: CGPoint(x: x + arm, y: y))
            context.move(to: CGPoint(x: x, y: y - arm * 0.72))
            context.addLine(to: CGPoint(x: x, y: y + arm * 0.72))
            if i.isMultiple(of: 4) {
                context.move(to: CGPoint(x: x - arm * 0.62, y: y - arm * 0.62))
                context.addLine(to: CGPoint(x: x + arm * 0.62, y: y + arm * 0.62))
            }
            context.strokePath()
        }
        context.restoreGState()
    }

    private func drawTemporalRiftContainment(in rect: NSRect, context: CGContext, colors: IndicatorPaletteColors, opening: CGFloat) {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        context.saveGState()
        context.setBlendMode(.plusLighter)
        context.setLineCap(.round)

        for band in 0..<5 {
            let progress = CGFloat(band) / 4
            let radiusX = rect.height * (0.62 + progress * 0.62 + opening * 0.20)
            let radiusY = radiusX * (0.28 + progress * 0.06)
            let alpha = 0.085 - progress * 0.018
            context.setStrokeColor((band.isMultiple(of: 2) ? colors.spark : colors.mid).withAlphaComponent(alpha).cgColor)
            context.setLineWidth(0.82 + progress * 0.34)
            context.setShadow(offset: .zero, blur: 16 + progress * 14, color: colors.mid.withAlphaComponent(alpha * 1.2).cgColor)
            context.setLineDash(phase: CGFloat(phase) * 2.2 + progress * 5, lengths: [7.0 - progress * 2.5, 3.0 + progress * 2.0])
            strokeTemporalArc(center: center, radiusX: radiusX, radiusY: radiusY, start: 0, end: CGFloat.pi * 2, context: context)
        }
        context.setLineDash(phase: 0, lengths: [])

        for beam in 0..<7 {
            let offset = (CGFloat(beam) - 3) * rect.width * 0.055
            let beamRect = NSRect(x: center.x + offset - 0.45, y: rect.minY - 5, width: 0.9, height: rect.height + 10)
            drawLinearGradient(
                in: beamRect,
                context: context,
                colors: [colors.low.withAlphaComponent(0), colors.spark.withAlphaComponent(0.08 + opening * 0.08), colors.high.withAlphaComponent(0)],
                locations: [0, 0.52, 1],
                start: CGPoint(x: beamRect.midX, y: beamRect.maxY),
                end: CGPoint(x: beamRect.midX, y: beamRect.minY)
            )
        }
        context.restoreGState()
    }

    private func drawTemporalRiftHaze(in rect: NSRect, context: CGContext, colors: IndicatorPaletteColors, opening: CGFloat, stabilized: Bool) {
        context.saveGState()
        context.setBlendMode(.plusLighter)
        let hazeHeight = rect.height * (0.42 + opening * 0.22)
        let upper = NSRect(x: rect.minX, y: rect.midY, width: rect.width, height: hazeHeight)
        drawLinearGradient(
            in: upper,
            context: context,
            colors: [colors.high.withAlphaComponent(0), colors.mid.withAlphaComponent(stabilized ? 0.035 : 0.055), colors.spark.withAlphaComponent(0)],
            locations: [0, 0.48, 1],
            start: CGPoint(x: upper.midX, y: upper.maxY),
            end: CGPoint(x: upper.midX, y: upper.minY)
        )
        let lower = NSRect(x: rect.minX, y: rect.midY - hazeHeight, width: rect.width, height: hazeHeight)
        drawLinearGradient(
            in: lower,
            context: context,
            colors: [colors.low.withAlphaComponent(0), colors.mid.withAlphaComponent(stabilized ? 0.028 : 0.046), colors.high.withAlphaComponent(0)],
            locations: [0, 0.52, 1],
            start: CGPoint(x: lower.midX, y: lower.minY),
            end: CGPoint(x: lower.midX, y: lower.maxY)
        )
        context.restoreGState()
    }

    // MARK: - Crystal Lens

    private func drawCrystalLens(in rect: NSRect, context: CGContext) {
        let colors = activePaletteColors()
        let energy = averageLevel()
        let stabilized = mode == .transcribing
        let pulse = CGFloat(0.5 + 0.5 * sin(phase * 1.35))
        let fieldRect = rect.insetBy(dx: -10, dy: -6)

        context.saveGState()
        context.clip(to: fieldRect)

        drawCrystalLensField(in: fieldRect, context: context, colors: colors, energy: energy, stabilized: stabilized)
        drawCrystalLensPrism(in: rect, context: context, colors: colors, energy: energy, stabilized: stabilized, pulse: pulse)
        drawCrystalLensBeams(in: rect, context: context, colors: colors, energy: energy, stabilized: stabilized, pulse: pulse)
        drawCrystalLensCaustics(in: rect, context: context, colors: colors, energy: energy, stabilized: stabilized)
        drawCrystalLensCore(in: rect, context: context, colors: colors, energy: energy, stabilized: stabilized, pulse: pulse)
        drawCrystalLensParticles(in: rect, context: context, colors: colors, energy: energy, stabilized: stabilized)

        context.restoreGState()
    }

    private func drawCrystalLensField(in rect: NSRect, context: CGContext, colors: IndicatorPaletteColors, energy: CGFloat, stabilized: Bool) {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let pulse = CGFloat(0.5 + 0.5 * sin(phase * 0.62))
        let w = rect.width * (0.28 + energy * 0.18 + pulse * 0.06)
        let h = rect.height * (1.15 + energy * 0.42 + pulse * 0.12)
        let fieldRect = NSRect(x: center.x - w * 0.5, y: center.y - h * 0.5, width: w, height: h)

        context.saveGState()
        context.setBlendMode(.plusLighter)
        context.addEllipse(in: fieldRect)
        context.clip()
        drawRadialGradient(
            in: fieldRect,
            context: context,
            colors: [colors.spark.withAlphaComponent(0.12 + energy * 0.08), colors.mid.withAlphaComponent(0.06), colors.low.withAlphaComponent(0), NSColor.black.withAlphaComponent(0)],
            locations: [0, 0.32, 0.68, 1],
            center: center
        )
        context.restoreGState()
    }

    private func drawCrystalLensPrism(in rect: NSRect, context: CGContext, colors: IndicatorPaletteColors, energy: CGFloat, stabilized: Bool, pulse: CGFloat) {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let d = rect.height * (0.22 + energy * 0.14 + pulse * 0.05)
        let prismPath = CGMutablePath()
        prismPath.move(to: CGPoint(x: center.x, y: center.y - d))
        prismPath.addLine(to: CGPoint(x: center.x + d * 0.58, y: center.y + d * 0.38))
        prismPath.addLine(to: CGPoint(x: center.x - d * 0.58, y: center.y + d * 0.38))
        prismPath.closeSubpath()

        context.saveGState()
        context.setBlendMode(.plusLighter)
        context.addPath(prismPath)
        context.setFillColor(colors.mid.withAlphaComponent(0.14 + energy * 0.12).cgColor)
        context.setShadow(offset: .zero, blur: 14 + energy * 16, color: colors.mid.withAlphaComponent(0.22 + energy * 0.14).cgColor)
        context.fillPath()
        context.restoreGState()

        context.saveGState()
        context.setBlendMode(.plusLighter)
        context.addPath(prismPath)
        context.setStrokeColor(colors.spark.withAlphaComponent(0.38 + energy * 0.24).cgColor)
        context.setLineWidth(0.9 + energy * 0.4)
        context.setShadow(offset: .zero, blur: 6 + energy * 8, color: colors.spark.withAlphaComponent(0.28 + energy * 0.16).cgColor)
        context.strokePath()
        context.restoreGState()
    }

    private func drawCrystalLensBeams(in rect: NSRect, context: CGContext, colors: IndicatorPaletteColors, energy: CGFloat, stabilized: Bool, pulse: CGFloat) {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let beamCount = stabilized ? 5 : 7
        let spread = stabilized ? 0.42 : 0.58 + energy * 0.22
        let sweep = CGFloat(0.5 + 0.5 * sin(phase * (stabilized ? 0.22 : 0.48)))
        let palette = [colors.low, colors.mid, colors.high, colors.spark]

        for i in 0..<beamCount {
            let t = CGFloat(i) / CGFloat(max(1, beamCount - 1))
            let angle = (t - 0.5) * spread + CGFloat(sin(phase * 0.38 + Float(i) * 0.72)) * 0.08
            let audio = mirroredLevel(at: Int(t * CGFloat(levelCount - 1)))
            let len = rect.width * (0.32 + energy * 0.18 + audio * 0.28 + sweep * 0.12)
            let ex = center.x + cos(angle) * len
            let ey = center.y + sin(angle) * len * 0.55
            let color = palette[i % palette.count]
            let alpha = 0.10 + energy * 0.16 + audio * 0.18 + pulse * 0.05

            context.saveGState()
            context.setBlendMode(.plusLighter)
            context.setStrokeColor(color.withAlphaComponent(alpha * 0.42).cgColor)
            context.setLineWidth(4.2 + energy * 2.8 + audio * 1.4)
            context.setShadow(offset: .zero, blur: 11 + audio * 10, color: color.withAlphaComponent(alpha).cgColor)
            context.move(to: center)
            context.addLine(to: CGPoint(x: ex, y: ey))
            context.strokePath()
            context.restoreGState()

            context.saveGState()
            context.setBlendMode(.plusLighter)
            context.setStrokeColor(colors.spark.withAlphaComponent(alpha * 0.62).cgColor)
            context.setLineWidth(0.45 + audio * 0.36)
            context.setShadow(offset: .zero, blur: 4, color: colors.spark.withAlphaComponent(alpha * 0.48).cgColor)
            context.move(to: center)
            context.addLine(to: CGPoint(x: ex, y: ey))
            context.strokePath()
            context.restoreGState()
        }
    }

    private func drawCrystalLensCaustics(in rect: NSRect, context: CGContext, colors: IndicatorPaletteColors, energy: CGFloat, stabilized: Bool) {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let count = stabilized ? 4 : 6
        let palette = [colors.low, colors.mid, colors.high, colors.spark]

        for i in 0..<count {
            let seed = Float(i) * 2.37
            let t = CGFloat((sin(phase * 0.35 + seed) + 1) * 0.5)
            let audio = mirroredLevel(at: Int(t * CGFloat(levelCount - 1)))
            let alpha = 0.06 + audio * 0.14 + energy * 0.08
            let x = center.x + CGFloat(cos(phase * 0.52 + seed)) * rect.width * (0.12 + t * 0.22)
            let y = center.y + CGFloat(sin(phase * 0.41 + seed)) * rect.height * (0.14 + audio * 0.16)
            let w = rect.width * (0.08 + audio * 0.12 + energy * 0.06)
            let h = rect.height * (0.28 + audio * 0.22 + energy * 0.10)
            let color = palette[i % palette.count]
            let causticRect = NSRect(x: x - w * 0.5, y: y - h * 0.5, width: w, height: h)

            context.saveGState()
            context.setBlendMode(.plusLighter)
            context.addEllipse(in: causticRect)
            context.clip()
            drawRadialGradient(
                in: causticRect,
                context: context,
                colors: [color.withAlphaComponent(alpha), colors.spark.withAlphaComponent(alpha * 0.38), color.withAlphaComponent(0)],
                locations: [0, 0.42, 1],
                center: CGPoint(x: x, y: y)
            )
            context.restoreGState()
        }
    }

    private func drawCrystalLensCore(in rect: NSRect, context: CGContext, colors: IndicatorPaletteColors, energy: CGFloat, stabilized: Bool, pulse: CGFloat) {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let w = rect.width * (0.06 + energy * 0.08 + pulse * 0.03)
        let h = rect.height * (0.18 + energy * 0.12 + pulse * 0.04)
        let coreRect = NSRect(x: center.x - w, y: center.y - h, width: w * 2, height: h * 2)

        context.saveGState()
        context.setBlendMode(.plusLighter)
        context.addEllipse(in: coreRect)
        context.clip()
        drawRadialGradient(
            in: coreRect,
            context: context,
            colors: [colors.spark.withAlphaComponent(0.32 + energy * 0.22), colors.mid.withAlphaComponent(0.16), colors.low.withAlphaComponent(0)],
            locations: [0, 0.42, 1],
            center: center
        )
        context.restoreGState()
    }

    private func drawCrystalLensParticles(in rect: NSRect, context: CGContext, colors: IndicatorPaletteColors, energy: CGFloat, stabilized: Bool) {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let palette = [colors.spark, colors.high, colors.mid]

        context.saveGState()
        context.setBlendMode(.plusLighter)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        for i in 0..<12 {
            let seed = Float(i) * 1.83
            let t = CGFloat((sin(phase * 0.46 + seed) + 1) * 0.5)
            let audio = mirroredLevel(at: Int(t * CGFloat(levelCount - 1)))
            let burst = max(0, audio - 0.30) / 0.70
            let alpha = min(0.72, 0.08 + burst * 0.52 + CGFloat(pow(Double(max(0, sin(phase * 2.1 + seed))), 2.0)) * 0.14)
            guard alpha > 0.06 else { continue }

            let x = rect.minX + rect.width * t
            let y = center.y + CGFloat(cos(phase * 0.58 + seed)) * rect.height * (0.12 + audio * 0.22)
            let arm = 0.55 + burst * 2.4
            let color = palette[i % palette.count]

            context.setShadow(offset: .zero, blur: 4 + arm * 2.2, color: color.withAlphaComponent(alpha).cgColor)
            context.setStrokeColor(color.withAlphaComponent(alpha).cgColor)
            context.setLineWidth(0.38 + burst * 0.32)
            context.move(to: CGPoint(x: x - arm, y: y))
            context.addLine(to: CGPoint(x: x + arm, y: y))
            context.move(to: CGPoint(x: x, y: y - arm * 0.72))
            context.addLine(to: CGPoint(x: x, y: y + arm * 0.72))
            context.strokePath()
        }
        context.restoreGState()
    }

    // MARK: - Cosmic Storm

    private func drawCosmicStorm(in rect: NSRect, context: CGContext) {
        let colors = activePaletteColors()
        let energy = averageLevel()
        let stabilized = mode == .transcribing
        let pulse = CGFloat(0.5 + 0.5 * sin(phase * 1.15))
        let fieldRect = rect.insetBy(dx: -10, dy: -6)

        context.saveGState()
        context.clip(to: fieldRect)

        drawCosmicStormField(in: rect, context: context, colors: colors, energy: energy, stabilized: stabilized, pulse: pulse)
        drawCosmicStormEnvelopes(in: rect, context: context, colors: colors, energy: energy, stabilized: stabilized)
        drawCosmicStormLightning(in: rect, context: context, colors: colors, energy: energy, stabilized: stabilized)
        drawCosmicStormCore(in: rect, context: context, colors: colors, energy: energy, stabilized: stabilized, pulse: pulse)
        drawCosmicStormDebris(in: rect, context: context, colors: colors, energy: energy, stabilized: stabilized)

        context.restoreGState()
    }

    private func drawCosmicStormField(in rect: NSRect, context: CGContext, colors: IndicatorPaletteColors, energy: CGFloat, stabilized: Bool, pulse: CGFloat) {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let w = rect.width * (0.34 + energy * 0.22 + pulse * 0.06)
        let h = rect.height * (1.2 + energy * 0.48)
        let fieldRect = NSRect(x: center.x - w * 0.5, y: center.y - h * 0.5, width: w, height: h)

        context.saveGState()
        context.setBlendMode(.plusLighter)
        context.addEllipse(in: fieldRect)
        context.clip()
        drawRadialGradient(
            in: fieldRect,
            context: context,
            colors: [colors.mid.withAlphaComponent(0.12 + energy * 0.10), colors.low.withAlphaComponent(0.06), NSColor.black.withAlphaComponent(0)],
            locations: [0, 0.42, 1],
            center: center
        )
        context.restoreGState()
    }

    private func drawCosmicStormEnvelopes(in rect: NSRect, context: CGContext, colors: IndicatorPaletteColors, energy: CGFloat, stabilized: Bool) {
        let path = makeEnvelopePath(in: rect, amplitude: 0.95, minimumHeight: 1.8, phaseOffset: 0)
        let inner = makeEnvelopePath(in: rect.insetBy(dx: 3, dy: 1), amplitude: 0.68, minimumHeight: 1.0, phaseOffset: 2.1)

        stroke(path, context: context, color: colors.low.withAlphaComponent(0.32), width: 10.0, blur: 14)
        stroke(inner, context: context, color: colors.mid.withAlphaComponent(0.18), width: 5, blur: 10)
        fill(path, context: context, colors: [colors.low.withAlphaComponent(0.38), colors.mid.withAlphaComponent(0.52), colors.high.withAlphaComponent(0.38)])
        stroke(path, context: context, color: colors.spark.withAlphaComponent(0.48), width: 1.0, blur: 3)
    }

    private func drawCosmicStormLightning(in rect: NSRect, context: CGContext, colors: IndicatorPaletteColors, energy: CGFloat, stabilized: Bool) {
        let palette = [colors.spark, colors.high, colors.mid]
        let boltCount = stabilized ? 4 : 6

        context.saveGState()
        context.setBlendMode(.plusLighter)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        for i in 0..<boltCount {
            let seed = Float(i) * 3.17
            let t = CGFloat((sin(phase * 0.38 + seed) + 1) * 0.5)
            let audio = mirroredLevel(at: Int(t * CGFloat(levelCount - 1)))
            let alpha = 0.08 + audio * 0.22 + energy * 0.10
            let color = palette[i % palette.count]
            let start = CGPoint(
                x: rect.minX + rect.width * t,
                y: rect.midY + CGFloat(cos(phase * 0.52 + seed)) * rect.height * 0.22
            )
            let segs = 4 + (i % 2)
            var current = start
            context.setShadow(offset: .zero, blur: 8 + audio * 12, color: color.withAlphaComponent(alpha * 0.9).cgColor)
            context.setStrokeColor(color.withAlphaComponent(alpha * 0.52).cgColor)
            context.setLineWidth(2.6 + audio * 2.0)
            context.beginPath()
            context.move(to: current)
            for seg in 0..<segs {
                let jitterX = CGFloat(cos(phase * 1.2 + seed + Float(seg) * 2.7)) * rect.width * 0.04
                let jitterY = CGFloat(sin(phase * 0.9 + seed + Float(seg) * 1.8)) * rect.height * 0.08
                current = CGPoint(x: current.x + jitterX, y: current.y + jitterY)
                context.addLine(to: current)
            }
            context.strokePath()
        }

        context.restoreGState()
    }

    private func drawCosmicStormCore(in rect: NSRect, context: CGContext, colors: IndicatorPaletteColors, energy: CGFloat, stabilized: Bool, pulse: CGFloat) {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let w = rect.width * (0.08 + energy * 0.10 + pulse * 0.03)
        let h = rect.height * (0.22 + energy * 0.14)
        let coreRect = NSRect(x: center.x - w, y: center.y - h, width: w * 2, height: h * 2)

        context.saveGState()
        context.setBlendMode(.plusLighter)
        context.addEllipse(in: coreRect)
        context.clip()
        drawRadialGradient(
            in: coreRect,
            context: context,
            colors: [colors.spark.withAlphaComponent(0.28 + energy * 0.22), colors.mid.withAlphaComponent(0.14), colors.low.withAlphaComponent(0)],
            locations: [0, 0.42, 1],
            center: center
        )
        context.restoreGState()
    }

    private func drawCosmicStormDebris(in rect: NSRect, context: CGContext, colors: IndicatorPaletteColors, energy: CGFloat, stabilized: Bool) {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let palette = [colors.spark, colors.high, colors.mid]

        context.saveGState()
        context.setBlendMode(.plusLighter)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        for i in 0..<10 {
            let seed = Float(i) * 2.47
            let t = CGFloat((sin(phase * 0.44 + seed) + 1) * 0.5)
            let audio = mirroredLevel(at: Int(t * CGFloat(levelCount - 1)))
            let burst = max(0, audio - 0.28) / 0.72
            let alpha = min(0.72, 0.06 + burst * 0.48 + CGFloat(pow(Double(max(0, sin(phase * 2.0 + seed))), 2.0)) * 0.12)
            guard alpha > 0.05 else { continue }

            let x = rect.minX + rect.width * t
            let y = center.y + CGFloat(cos(phase * 0.62 + seed)) * rect.height * (0.14 + audio * 0.26)
            let arm = 0.5 + burst * 2.2
            let color = palette[i % palette.count]

            context.setShadow(offset: .zero, blur: 3 + arm * 2.0, color: color.withAlphaComponent(alpha).cgColor)
            context.setStrokeColor(color.withAlphaComponent(alpha).cgColor)
            context.setLineWidth(0.36 + burst * 0.30)
            context.move(to: CGPoint(x: x - arm, y: y))
            context.addLine(to: CGPoint(x: x + arm, y: y))
            context.move(to: CGPoint(x: x, y: y - arm * 0.72))
            context.addLine(to: CGPoint(x: x, y: y + arm * 0.72))
            context.strokePath()
        }
        context.restoreGState()
    }

    // MARK: - Neural Network

    private func drawNeuralNetwork(in rect: NSRect, context: CGContext) {
        let colors = activePaletteColors()
        let energy = averageLevel()
        let stabilized = mode == .transcribing
        let fieldRect = rect.insetBy(dx: -8, dy: -4)

        context.saveGState()
        context.clip(to: fieldRect)

        drawNeuralNetworkNodes(in: rect, context: context, colors: colors, energy: energy, stabilized: stabilized)
        drawNeuralNetworkSynapses(in: rect, context: context, colors: colors, energy: energy, stabilized: stabilized)
        drawNeuralNetworkPulses(in: rect, context: context, colors: colors, energy: energy, stabilized: stabilized)

        context.restoreGState()
    }

    private func drawNeuralNetworkNodes(in rect: NSRect, context: CGContext, colors: IndicatorPaletteColors, energy: CGFloat, stabilized: Bool) {
        let palette = [colors.spark, colors.mid, colors.high]
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let nodeCount = stabilized ? 9 : 11

        context.saveGState()
        context.setBlendMode(.plusLighter)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        for i in 0..<nodeCount {
            let seed = Float(i) * 1.93
            let t = CGFloat(i) / CGFloat(nodeCount - 1)
            let audio = mirroredLevel(at: Int(t * CGFloat(levelCount - 1)))
            let x = rect.minX + rect.width * t + CGFloat(sin(phase * 0.62 + seed)) * rect.width * 0.035
            let y = center.y + CGFloat(cos(phase * 0.58 + seed)) * rect.height * (0.18 + audio * 0.42)
            let pulse = CGFloat(0.5 + 0.5 * sin(phase * 1.8 + seed))
            let r = 2.8 + pulse * 2.2 + audio * 5.0 + energy * 2.0
            let color = palette[i % palette.count]
            let alpha = 0.48 + audio * 0.42 + pulse * 0.22 + energy * 0.14

            context.setShadow(offset: .zero, blur: 8 + audio * 12 + pulse * 5, color: color.withAlphaComponent(alpha * 0.9).cgColor)
            context.setStrokeColor(color.withAlphaComponent(alpha).cgColor)
            context.setLineWidth(0.75 + audio * 0.85 + pulse * 0.45)
            context.move(to: CGPoint(x: x - r, y: y))
            context.addLine(to: CGPoint(x: x + r, y: y))
            context.move(to: CGPoint(x: x, y: y - r))
            context.addLine(to: CGPoint(x: x, y: y + r))
            context.strokePath()

            if audio > 0.12 {
                let d = r * 0.72
                context.setStrokeColor(colors.spark.withAlphaComponent(alpha * 0.65).cgColor)
                context.setLineWidth(0.5 + audio * 0.45)
                context.setShadow(offset: .zero, blur: 6 + audio * 8, color: colors.spark.withAlphaComponent(alpha * 0.5).cgColor)
                context.move(to: CGPoint(x: x - d, y: y - d))
                context.addLine(to: CGPoint(x: x + d, y: y + d))
                context.move(to: CGPoint(x: x + d, y: y - d))
                context.addLine(to: CGPoint(x: x - d, y: y + d))
                context.strokePath()
            }
        }

        context.restoreGState()
    }

    private func drawNeuralNetworkSynapses(in rect: NSRect, context: CGContext, colors: IndicatorPaletteColors, energy: CGFloat, stabilized: Bool) {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let nodeCount = stabilized ? 9 : 11
        var nodes: [CGPoint] = []

        for i in 0..<nodeCount {
            let seed = Float(i) * 1.93
            let t = CGFloat(i) / CGFloat(nodeCount - 1)
            let audio = mirroredLevel(at: Int(t * CGFloat(levelCount - 1)))
            let x = rect.minX + rect.width * t + CGFloat(sin(phase * 0.62 + seed)) * rect.width * 0.035
            let y = center.y + CGFloat(cos(phase * 0.58 + seed)) * rect.height * (0.18 + audio * 0.28)
            nodes.append(CGPoint(x: x, y: y))
        }

        context.saveGState()
        context.setBlendMode(.plusLighter)
        context.setLineCap(.round)

        for i in 0..<(nodes.count - 1) {
            let t = CGFloat(i) / CGFloat(max(1, nodes.count - 2))
            let audio = mirroredLevel(at: Int(t * CGFloat(levelCount - 1)))
            let alpha = 0.14 + audio * 0.22 + energy * 0.12 + CGFloat(i % 3) * 0.03
            let lw = 0.55 + audio * 0.65
            context.setStrokeColor((i.isMultiple(of: 2) ? colors.mid : colors.high).withAlphaComponent(alpha).cgColor)
            context.setLineWidth(lw)
            context.setShadow(offset: .zero, blur: 4 + audio * 6, color: (i.isMultiple(of: 2) ? colors.mid : colors.high).withAlphaComponent(alpha * 0.7).cgColor)
            context.move(to: nodes[i])
            context.addLine(to: nodes[i + 1])
            context.strokePath()
        }

        for i in stride(from: 0, to: nodes.count - 2, by: 2) {
            let alpha = 0.10 + energy * 0.12
            context.setStrokeColor(colors.spark.withAlphaComponent(alpha).cgColor)
            context.setLineWidth(0.45 + energy * 0.35)
            context.setShadow(offset: .zero, blur: 4, color: colors.spark.withAlphaComponent(alpha * 0.6).cgColor)
            context.move(to: nodes[i])
            context.addLine(to: nodes[i + 2])
            context.strokePath()
        }
        context.restoreGState()
    }

    private func drawNeuralNetworkPulses(in rect: NSRect, context: CGContext, colors: IndicatorPaletteColors, energy: CGFloat, stabilized: Bool) {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let nodeCount = stabilized ? 9 : 11
        let palette = [colors.spark, colors.mid, colors.high]

        var nodes: [CGPoint] = []
        for i in 0..<nodeCount {
            let seed = Float(i) * 1.93
            let t = CGFloat(i) / CGFloat(nodeCount - 1)
            let audio = mirroredLevel(at: Int(t * CGFloat(levelCount - 1)))
            let x = rect.minX + rect.width * t + CGFloat(sin(phase * 0.62 + seed)) * rect.width * 0.035
            let y = center.y + CGFloat(cos(phase * 0.58 + seed)) * rect.height * (0.18 + audio * 0.28)
            nodes.append(CGPoint(x: x, y: y))
        }

        context.saveGState()
        context.setBlendMode(.plusLighter)
        context.setLineCap(.round)

        let travel = CGFloat(0.5 + 0.5 * sin(phase * (stabilized ? 0.22 : 0.48)))
        let beamCount = stabilized ? 2 : 4

        for b in 0..<beamCount {
            let seed = Float(b) * 2.71
            let t = travel + CGFloat(sin(phase * 0.34 + seed)) * 0.15
            let clampedT = max(0, min(1, t))
            let idx = Int(clampedT * CGFloat(nodeCount - 1))
            let nextIdx = min(nodeCount - 1, idx + 1)
            let frac = clampedT * CGFloat(nodeCount - 1) - CGFloat(idx)
            let x = nodes[idx].x + (nodes[nextIdx].x - nodes[idx].x) * frac
            let y = nodes[idx].y + (nodes[nextIdx].y - nodes[idx].y) * frac
            let color = palette[b % palette.count]
            let alpha = 0.32 + energy * 0.28

            context.setShadow(offset: .zero, blur: 10 + energy * 8, color: color.withAlphaComponent(alpha * 0.8).cgColor)
            context.setStrokeColor(color.withAlphaComponent(alpha).cgColor)
            context.setLineWidth(0.85 + energy * 0.65)
            let r: CGFloat = 1.8 + energy * 1.2
            context.move(to: CGPoint(x: x - r, y: y))
            context.addLine(to: CGPoint(x: x + r, y: y))
            context.move(to: CGPoint(x: x, y: y - r))
            context.addLine(to: CGPoint(x: x, y: y + r))
            context.strokePath()
        }
        context.restoreGState()
    }

    // MARK: - Plasma Vortex

    private func drawPlasmaVortex(in rect: NSRect, context: CGContext) {
        let colors = activePaletteColors()
        let energy = averageLevel()
        let stabilized = mode == .transcribing
        let pulse = CGFloat(0.5 + 0.5 * sin(phase * 1.28))
        let fieldRect = rect.insetBy(dx: -10, dy: -6)

        context.saveGState()
        context.clip(to: fieldRect)

        drawPlasmaVortexField(in: rect, context: context, colors: colors, energy: energy, stabilized: stabilized, pulse: pulse)
        drawPlasmaVortexSpirals(in: rect, context: context, colors: colors, energy: energy, stabilized: stabilized)
        drawPlasmaVortexCore(in: rect, context: context, colors: colors, energy: energy, stabilized: stabilized, pulse: pulse)
        drawPlasmaVortexFilaments(in: rect, context: context, colors: colors, energy: energy, stabilized: stabilized)
        drawPlasmaVortexDebris(in: rect, context: context, colors: colors, energy: energy, stabilized: stabilized)

        context.restoreGState()
    }

    private func drawPlasmaVortexField(in rect: NSRect, context: CGContext, colors: IndicatorPaletteColors, energy: CGFloat, stabilized: Bool, pulse: CGFloat) {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let w = rect.width * (0.32 + energy * 0.20 + pulse * 0.06)
        let h = rect.height * (1.15 + energy * 0.44)
        let fieldRect = NSRect(x: center.x - w * 0.5, y: center.y - h * 0.5, width: w, height: h)

        context.saveGState()
        context.setBlendMode(.plusLighter)
        context.addEllipse(in: fieldRect)
        context.clip()
        drawRadialGradient(
            in: fieldRect,
            context: context,
            colors: [colors.spark.withAlphaComponent(0.10 + energy * 0.08), colors.mid.withAlphaComponent(0.05), NSColor.black.withAlphaComponent(0)],
            locations: [0, 0.38, 1],
            center: center
        )
        context.restoreGState()
    }

    private func drawPlasmaVortexSpirals(in rect: NSRect, context: CGContext, colors: IndicatorPaletteColors, energy: CGFloat, stabilized: Bool) {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let palette = [colors.low, colors.mid, colors.high, colors.spark]
        let loopCount = stabilized ? 5 : 4

        for loop in 0..<loopCount {
            let progress = CGFloat(loop) / CGFloat(max(1, loopCount - 1))
            let audio = mirroredLevel(at: min(levelCount - 1, 6 + loop * 10))
            let rotation = CGFloat(phase) * (stabilized ? 0.22 : 0.58) + CGFloat(loop) * 0.72
            let radiusX = rect.height * (0.58 + progress * 0.58 + energy * 0.36 + audio * 0.22)
            let radiusY = radiusX * (0.26 + progress * 0.06)
            let arc = CGFloat.pi * (stabilized ? 1.65 : 0.52 + energy * 0.82 + audio * 0.42)
            let color = palette[loop % palette.count]
            let alpha = 0.065 + energy * 0.080 - progress * 0.012

            context.saveGState()
            context.setBlendMode(.plusLighter)
            context.setLineCap(.round)
            context.setLineDash(phase: CGFloat(loop) * 2.8 + CGFloat(phase) * 1.2, lengths: [2.8 + progress * 4.2, 4.2 + progress * 3.0])
            context.setShadow(offset: .zero, blur: 12 + progress * 10, color: color.withAlphaComponent(alpha).cgColor)
            context.setStrokeColor(color.withAlphaComponent(alpha).cgColor)
            context.setLineWidth(0.82 + progress * 0.32)
            strokeTemporalArc(center: center, radiusX: radiusX, radiusY: radiusY, start: rotation, end: rotation + arc, context: context)
            context.restoreGState()
        }
    }

    private func drawPlasmaVortexCore(in rect: NSRect, context: CGContext, colors: IndicatorPaletteColors, energy: CGFloat, stabilized: Bool, pulse: CGFloat) {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let w = rect.width * (0.07 + energy * 0.09 + pulse * 0.03)
        let h = rect.height * (0.20 + energy * 0.13)
        let coreRect = NSRect(x: center.x - w, y: center.y - h, width: w * 2, height: h * 2)

        context.saveGState()
        context.setBlendMode(.plusLighter)
        context.addEllipse(in: coreRect)
        context.clip()
        drawRadialGradient(
            in: coreRect,
            context: context,
            colors: [colors.spark.withAlphaComponent(0.28 + energy * 0.22), colors.mid.withAlphaComponent(0.14), colors.low.withAlphaComponent(0)],
            locations: [0, 0.42, 1],
            center: center
        )
        context.restoreGState()
    }

    private func drawPlasmaVortexFilaments(in rect: NSRect, context: CGContext, colors: IndicatorPaletteColors, energy: CGFloat, stabilized: Bool) {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let palette = [colors.spark, colors.high, colors.mid]

        context.saveGState()
        context.setBlendMode(.plusLighter)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        for i in 0..<6 {
            let seed = Float(i) * 2.83
            let t = CGFloat((sin(phase * 0.36 + seed) + 1) * 0.5)
            let audio = mirroredLevel(at: Int(t * CGFloat(levelCount - 1)))
            let reach = rect.width * (0.18 + audio * 0.18 + energy * 0.12)
            let angle = CGFloat(phase * 0.42) + CGFloat(i) * CGFloat.pi / 3.0
            let ex = center.x + cos(angle) * reach
            let ey = center.y + sin(angle) * reach * 0.55
            let color = palette[i % palette.count]
            let alpha = 0.08 + audio * 0.16 + energy * 0.08

            context.setShadow(offset: .zero, blur: 10 + audio * 10, color: color.withAlphaComponent(alpha).cgColor)
            context.setStrokeColor(color.withAlphaComponent(alpha * 0.42).cgColor)
            context.setLineWidth(3.8 + audio * 1.8)
            context.move(to: center)
            context.addLine(to: CGPoint(x: ex, y: ey))
            context.strokePath()

            context.setStrokeColor(colors.spark.withAlphaComponent(alpha * 0.52).cgColor)
            context.setLineWidth(0.38 + audio * 0.32)
            context.setShadow(offset: .zero, blur: 4, color: colors.spark.withAlphaComponent(alpha * 0.48).cgColor)
            context.move(to: center)
            context.addLine(to: CGPoint(x: ex, y: ey))
            context.strokePath()
        }
        context.restoreGState()
    }

    private func drawPlasmaVortexDebris(in rect: NSRect, context: CGContext, colors: IndicatorPaletteColors, energy: CGFloat, stabilized: Bool) {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let palette = [colors.spark, colors.high, colors.mid]

        context.saveGState()
        context.setBlendMode(.plusLighter)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        for i in 0..<10 {
            let seed = Float(i) * 2.17
            let t = CGFloat((sin(phase * 0.42 + seed) + 1) * 0.5)
            let audio = mirroredLevel(at: Int(t * CGFloat(levelCount - 1)))
            let burst = max(0, audio - 0.30) / 0.70
            let alpha = min(0.72, 0.06 + burst * 0.48 + CGFloat(pow(Double(max(0, sin(phase * 2.0 + seed))), 2.0)) * 0.12)
            guard alpha > 0.05 else { continue }

            let x = rect.minX + rect.width * t
            let y = center.y + CGFloat(cos(phase * 0.58 + seed)) * rect.height * (0.12 + audio * 0.22)
            let arm = 0.5 + burst * 2.2
            let color = palette[i % palette.count]

            context.setShadow(offset: .zero, blur: 3 + arm * 2.0, color: color.withAlphaComponent(alpha).cgColor)
            context.setStrokeColor(color.withAlphaComponent(alpha).cgColor)
            context.setLineWidth(0.36 + burst * 0.30)
            context.move(to: CGPoint(x: x - arm, y: y))
            context.addLine(to: CGPoint(x: x + arm, y: y))
            context.move(to: CGPoint(x: x, y: y - arm * 0.72))
            context.addLine(to: CGPoint(x: x, y: y + arm * 0.72))
            context.strokePath()
        }
        context.restoreGState()
    }

    // MARK: - Xeno Lattice

    private func drawXenoLattice(in rect: NSRect, context: CGContext) {
        let colors = activePaletteColors()
        let nodeCount = 11
        let energy = averageLevel()
        let fieldRect = rect.insetBy(dx: 4, dy: 2)

        context.saveGState()
        context.setBlendMode(.plusLighter)
        context.clip(to: fieldRect.insetBy(dx: -10, dy: -8))
        context.setLineCap(.round)
        context.setLineJoin(.round)

        let nodes = xenoNodes(in: fieldRect, count: nodeCount, energy: energy)
        drawXenoVoidFolds(in: fieldRect, context: context, colors: colors, energy: energy, intense: mode == .transcribing)
        drawXenoLinks(nodes: nodes, context: context, colors: colors, intense: mode == .transcribing)
        drawXenoPrismShards(in: fieldRect, nodes: nodes, context: context, colors: colors, energy: energy, intense: mode == .transcribing)
        drawXenoNodes(nodes: nodes, context: context, colors: colors, energy: energy)

        switch mode {
        case .recording:
            drawXenoListeningField(in: fieldRect, context: context, colors: colors, energy: energy)
            drawXenoVoiceBursts(in: fieldRect, nodes: nodes, context: context, colors: colors, energy: energy)
        case .transcribing:
            drawXenoComputationField(in: fieldRect, nodes: nodes, context: context, colors: colors, energy: energy)
            drawXenoLockShards(in: fieldRect, nodes: nodes, context: context, colors: colors, energy: energy)
        }

        context.restoreGState()
    }

    // MARK: - Unicorn Sparklepop

    private func drawUnicornSparklepop(in rect: NSRect, context: CGContext) {
        let colors = activePaletteColors()
        let energy = averageLevel()
        let fieldRect = rect.insetBy(dx: -10, dy: -7)
        let stabilized = mode == .transcribing
        let path = makeEnvelopePath(in: rect, amplitude: stabilized ? 0.72 : 0.92, minimumHeight: 1.8, phaseOffset: stabilized ? 1.1 : 0)
        let frostingPath = makeEnvelopePath(in: rect.insetBy(dx: 5, dy: 2), amplitude: stabilized ? 0.42 : 0.58, minimumHeight: 1.0, phaseOffset: 2.6)

        context.saveGState()
        context.setBlendMode(.plusLighter)
        context.clip(to: fieldRect)

        drawCandyRainbowVeil(in: fieldRect, context: context, colors: colors, energy: energy, stabilized: stabilized)
        stroke(path, context: context, color: colors.mid.withAlphaComponent(0.42), width: 10.5, blur: 18)
        fill(path, context: context, colors: [colors.low.withAlphaComponent(0.44), colors.mid.withAlphaComponent(0.62), colors.high.withAlphaComponent(0.36)])
        stroke(frostingPath, context: context, color: colors.spark.withAlphaComponent(0.58), width: 1.2, blur: 6)
        drawCandyRibbonSwirls(in: rect, context: context, colors: colors, energy: energy, stabilized: stabilized)
        drawUnicornHoofprints(in: rect, context: context, colors: colors, energy: energy)

        switch mode {
        case .recording:
            drawSparklepopListeningHearts(in: rect, context: context, colors: colors, energy: energy)
        case .transcribing:
            drawSparklepopTranscribingCarousel(in: rect, context: context, colors: colors, energy: energy)
        }

        drawCandyGlitter(in: rect, context: context, colors: colors, energy: energy, count: stabilized ? 28 : 22)
        context.restoreGState()
    }

    private func drawCandyRainbowVeil(in rect: NSRect, context: CGContext, colors: IndicatorPaletteColors, energy: CGFloat, stabilized: Bool) {
        let shimmer = CGFloat(0.5 + 0.5 * sin(phase * 0.34))
        let showRainbow = stabilized || shimmer > 0.36
        guard showRainbow else { return }

        let alpha = (stabilized ? 0.08 : 0.035) + shimmer * 0.08 + energy * 0.08
        let rainbow = [
            colors.low,
            NSColor(calibratedRed: 1.00, green: 0.55, blue: 0.78, alpha: 1),
            colors.spark,
            NSColor(calibratedRed: 0.58, green: 1.00, blue: 0.74, alpha: 1),
            colors.high,
            colors.mid
        ]

        context.saveGState()
        context.setLineCap(.round)
        context.setShadow(offset: .zero, blur: 12, color: colors.mid.withAlphaComponent(alpha).cgColor)
        for band in 0..<6 {
            let y = rect.midY - rect.height * 0.46 + CGFloat(band) * rect.height * 0.17
            let wobble = CGFloat(sin(phase * (0.42 + Float(band) * 0.04) + Float(band))) * 3.4
            context.beginPath()
            for step in 0..<30 {
                let t = CGFloat(step) / 29
                let x = rect.minX + rect.width * t
                let arc = sin(t * .pi) * rect.height * (0.18 + CGFloat(band) * 0.012)
                let point = CGPoint(x: x, y: y + arc + wobble)
                if step == 0 { context.move(to: point) } else { context.addLine(to: point) }
            }
            context.setStrokeColor(rainbow[band].withAlphaComponent(alpha * (1.05 - CGFloat(band) * 0.08)).cgColor)
            context.setLineWidth(1.0 + CGFloat(band).truncatingRemainder(dividingBy: 2) * 0.35)
            context.strokePath()
        }
        context.restoreGState()
    }

    private func drawCandyRibbonSwirls(in rect: NSRect, context: CGContext, colors: IndicatorPaletteColors, energy: CGFloat, stabilized: Bool) {
        let ribbonCount = stabilized ? 4 : 3
        context.saveGState()
        context.setLineCap(.round)
        context.setLineJoin(.round)
        for ribbon in 0..<ribbonCount {
            let color = [colors.low, colors.mid, colors.high, colors.spark][ribbon % 4]
            context.beginPath()
            for step in 0..<42 {
                let t = CGFloat(step) / 41
                let audio = mirroredLevel(at: Int(t * CGFloat(levelCount - 1)))
                let curl = CGFloat(sin(phase * (1.05 + Float(ribbon) * 0.14) + Float(t) * 19 + Float(ribbon) * 1.8))
                let yBase = rect.midY + (CGFloat(ribbon) - CGFloat(ribbonCount - 1) * 0.5) * rect.height * 0.13
                let point = CGPoint(
                    x: rect.minX + rect.width * t,
                    y: yBase + curl * rect.height * (0.05 + audio * 0.16 + energy * 0.06)
                )
                if step == 0 { context.move(to: point) } else { context.addLine(to: point) }
            }
            context.setShadow(offset: .zero, blur: 7 + energy * 9, color: color.withAlphaComponent(0.28).cgColor)
            context.setStrokeColor(color.withAlphaComponent(0.24 + energy * 0.24).cgColor)
            context.setLineWidth(0.8 + CGFloat(ribbon) * 0.12)
            context.strokePath()
        }
        context.restoreGState()
    }

    private func drawSparklepopListeningHearts(in rect: NSRect, context: CGContext, colors: IndicatorPaletteColors, energy: CGFloat) {
        for index in 0..<7 {
            let t = CGFloat(index) / 6
            let audio = mirroredLevel(at: Int(t * CGFloat(levelCount - 1)))
            let float = CGFloat(sin(phase * 1.18 + Float(index) * 1.37))
            let scale = 2.2 + audio * 6.2 + energy * 2.4 + CGFloat(index % 2) * 0.8
            let center = CGPoint(x: rect.minX + rect.width * t, y: rect.midY + float * rect.height * (0.18 + audio * 0.18))
            let color = index.isMultiple(of: 2) ? colors.low : colors.mid
            let alpha = 0.16 + audio * 0.42 + energy * 0.18
            drawHeart(center: center, size: scale, context: context, color: color.withAlphaComponent(alpha), filled: index.isMultiple(of: 3))
        }
    }

    private func drawSparklepopTranscribingCarousel(in rect: NSRect, context: CGContext, colors: IndicatorPaletteColors, energy: CGFloat) {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let pulse = CGFloat(0.5 + 0.5 * sin(phase * 2.1))
        let haloSize = rect.height * (0.44 + pulse * 0.14 + energy * 0.18)

        context.saveGState()
        context.setShadow(offset: .zero, blur: 18 + pulse * 12, color: colors.mid.withAlphaComponent(0.42).cgColor)
        drawHeart(center: center, size: haloSize, context: context, color: colors.mid.withAlphaComponent(0.20 + pulse * 0.22), filled: true)
        drawHeart(center: center, size: haloSize * 1.28, context: context, color: colors.spark.withAlphaComponent(0.28 + pulse * 0.16), filled: false)

        for charm in 0..<8 {
            let angle = phase * 0.86 + Float(charm) * (.pi / 4)
            let radiusX = rect.width * (0.17 + energy * 0.04)
            let radiusY = rect.height * (0.34 + pulse * 0.08)
            let point = CGPoint(x: center.x + CGFloat(cos(angle)) * radiusX, y: center.y + CGFloat(sin(angle)) * radiusY)
            if charm.isMultiple(of: 2) {
                drawHeart(center: point, size: 2.4 + pulse * 1.8, context: context, color: colors.low.withAlphaComponent(0.32), filled: false)
            } else {
                drawTwinkle(center: point, arm: 1.5 + pulse * 1.4, context: context, color: colors.spark.withAlphaComponent(0.46))
            }
        }
        context.restoreGState()
    }

    private func drawUnicornHoofprints(in rect: NSRect, context: CGContext, colors: IndicatorPaletteColors, energy: CGFloat) {
        context.saveGState()
        context.setLineCap(.round)
        for step in 0..<5 {
            let t = CGFloat(step) / 4
            let x = rect.minX + rect.width * (0.10 + t * 0.80)
            let y = rect.midY + (step.isMultiple(of: 2) ? -1 : 1) * rect.height * (0.30 + 0.05 * CGFloat(sin(phase + Float(step))))
            let audio = mirroredLevel(at: Int(t * CGFloat(levelCount - 1)))
            let alpha = 0.08 + audio * 0.18 + energy * 0.08
            let size = 2.2 + audio * 2.6
            context.setStrokeColor(colors.high.withAlphaComponent(alpha).cgColor)
            context.setShadow(offset: .zero, blur: 5, color: colors.high.withAlphaComponent(alpha).cgColor)
            context.setLineWidth(0.55 + audio * 0.2)
            context.addArc(center: CGPoint(x: x, y: y), radius: size, startAngle: .pi * 0.15, endAngle: .pi * 0.85, clockwise: false)
            context.strokePath()
        }
        context.restoreGState()
    }

    private func drawCandyGlitter(in rect: NSRect, context: CGContext, colors: IndicatorPaletteColors, energy: CGFloat, count: Int) {
        for index in 0..<count {
            let seed = Float(index) * 1.913
            let t = CGFloat((sin(seed * 2.1) + 1) * 0.5)
            let drift = CGFloat(sin(phase * (0.52 + seed.truncatingRemainder(dividingBy: 0.17)) + seed)) * rect.width * 0.018
            let x = rect.minX + rect.width * t + drift
            let y = rect.midY + CGFloat(cos(seed * 1.7 + phase * 0.74)) * rect.height * 0.46
            let pulse = CGFloat(0.5 + 0.5 * sin(phase * 2.9 + seed))
            let arm = 0.55 + pulse * 1.5 + energy * 1.8
            let color = [colors.spark, colors.mid, colors.high, colors.low][index % 4]
            drawTwinkle(center: CGPoint(x: x, y: y), arm: arm, context: context, color: color.withAlphaComponent(0.16 + pulse * 0.28 + energy * 0.12))
        }
    }

    private func drawHeart(center: CGPoint, size: CGFloat, context: CGContext, color: NSColor, filled: Bool) {
        let path = CGMutablePath()
        let s = size
        path.move(to: CGPoint(x: center.x, y: center.y - s * 0.58))
        path.addCurve(to: CGPoint(x: center.x - s, y: center.y + s * 0.12), control1: CGPoint(x: center.x - s * 0.92, y: center.y - s * 0.08), control2: CGPoint(x: center.x - s * 1.08, y: center.y + s * 0.62))
        path.addCurve(to: CGPoint(x: center.x, y: center.y + s * 0.82), control1: CGPoint(x: center.x - s * 0.92, y: center.y + s * 0.88), control2: CGPoint(x: center.x - s * 0.22, y: center.y + s * 0.98))
        path.addCurve(to: CGPoint(x: center.x + s, y: center.y + s * 0.12), control1: CGPoint(x: center.x + s * 0.22, y: center.y + s * 0.98), control2: CGPoint(x: center.x + s * 0.92, y: center.y + s * 0.88))
        path.addCurve(to: CGPoint(x: center.x, y: center.y - s * 0.58), control1: CGPoint(x: center.x + s * 1.08, y: center.y + s * 0.62), control2: CGPoint(x: center.x + s * 0.92, y: center.y - s * 0.08))
        path.closeSubpath()

        context.saveGState()
        context.setShadow(offset: .zero, blur: max(3, size * 0.9), color: color.cgColor)
        context.addPath(path)
        if filled {
            context.setFillColor(color.cgColor)
            context.fillPath()
        } else {
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(max(0.45, size * 0.12))
            context.strokePath()
        }
        context.restoreGState()
    }

    private func drawTwinkle(center: CGPoint, arm: CGFloat, context: CGContext, color: NSColor) {
        context.saveGState()
        context.setLineCap(.round)
        context.setShadow(offset: .zero, blur: 5 + arm, color: color.cgColor)
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(max(0.35, arm * 0.16))
        context.move(to: CGPoint(x: center.x - arm, y: center.y))
        context.addLine(to: CGPoint(x: center.x + arm, y: center.y))
        context.move(to: CGPoint(x: center.x, y: center.y - arm))
        context.addLine(to: CGPoint(x: center.x, y: center.y + arm))
        context.move(to: CGPoint(x: center.x - arm * 0.58, y: center.y - arm * 0.58))
        context.addLine(to: CGPoint(x: center.x + arm * 0.58, y: center.y + arm * 0.58))
        context.move(to: CGPoint(x: center.x + arm * 0.58, y: center.y - arm * 0.58))
        context.addLine(to: CGPoint(x: center.x - arm * 0.58, y: center.y + arm * 0.58))
        context.strokePath()
        context.restoreGState()
    }

    // MARK: - Envelope Path

    private func makeEnvelopePath(in rect: NSRect, amplitude: CGFloat, minimumHeight: CGFloat, phaseOffset: Float) -> CGPath {
        let path = CGMutablePath()
        let count = levelCount
        guard count > 1 else { return path }

        for i in 0..<count {
            let xProgress = CGFloat(i) / CGFloat(count - 1)
            let level = mirroredLevel(at: i)
            let breathing = CGFloat(0.5 + 0.5 * sin(phase * 1.6 + Float(xProgress) * 13 + phaseOffset))
            let highFrequency = CGFloat(0.5 + 0.5 * sin(phase * 3.2 - Float(xProgress) * 31 + phaseOffset))
            let shaped = min(1, level * (0.82 + breathing * 0.22) + highFrequency * 0.025)
            let height = max(minimumHeight, rect.height * shaped * amplitude * 0.5)
            let point = CGPoint(x: rect.minX + rect.width * xProgress, y: rect.midY + height)
            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }

        for i in stride(from: count - 1, through: 0, by: -1) {
            let xProgress = CGFloat(i) / CGFloat(count - 1)
            let level = mirroredLevel(at: i)
            let breathing = CGFloat(0.5 + 0.5 * sin(phase * 1.6 + Float(xProgress) * 13 + phaseOffset))
            let highFrequency = CGFloat(0.5 + 0.5 * sin(phase * 3.2 - Float(xProgress) * 31 + phaseOffset))
            let shaped = min(1, level * (0.82 + breathing * 0.22) + highFrequency * 0.025)
            let height = max(minimumHeight, rect.height * shaped * amplitude * 0.5)
            path.addLine(to: CGPoint(x: rect.minX + rect.width * xProgress, y: rect.midY - height))
        }

        path.closeSubpath()
        return path
    }

    private func mirroredLevel(at index: Int) -> CGFloat {
        let clampedIndex = max(0, min(levelCount - 1, index))
        let half = levelCount / 2
        let mirrored = clampedIndex < half ? half - 1 - clampedIndex : clampedIndex - half
        let sourceIndex = max(0, min(levelCount - 1, half + mirrored))
        let raw = CGFloat(max(0, min(1, levels[sourceIndex])))
        return pow(raw, 0.72)
    }

    private func averageLevel() -> CGFloat {
        guard !levels.isEmpty else { return 0 }
        let total = levels.reduce(Float(0), +)
        return CGFloat(total / Float(levels.count))
    }

    private func activePaletteColors() -> IndicatorPaletteColors {
        colorPalette.colors(for: mode)
    }

    // MARK: - Xeno Helpers

    private func xenoNodes(in rect: NSRect, count: Int, energy: CGFloat) -> [CGPoint] {
        guard count > 1 else { return [] }
        return (0..<count).map { index in
            let t = CGFloat(index) / CGFloat(count - 1)
            let audio = mirroredLevel(at: Int(t * CGFloat(levelCount - 1)))
            let lane = CGFloat(sin(phase * 1.16 + Float(index) * 0.82))
            let micro = CGFloat(sin(phase * 2.7 - Float(index) * 1.31))
            let yOffset = lane * rect.height * (0.13 + audio * 0.25 + energy * 0.12) + micro * (0.8 + audio * 2.2)
            return CGPoint(x: rect.minX + rect.width * t, y: rect.midY + yOffset)
        }
    }

    private func drawXenoVoidFolds(in rect: NSRect, context: CGContext, colors: IndicatorPaletteColors, energy: CGFloat, intense: Bool) {
        let foldCount = intense ? 7 : 5
        context.saveGState()
        context.setBlendMode(.plusLighter)

        for fold in 0..<foldCount {
            let t = CGFloat(fold) / CGFloat(max(1, foldCount - 1))
            let audio = mirroredLevel(at: Int(t * CGFloat(levelCount - 1)))
            let drift = CGFloat(sin(phase * (0.46 + Float(fold) * 0.06) + Float(fold) * 1.2)) * rect.width * 0.035
            let skew = CGFloat(cos(phase * 0.52 + Float(fold))) * rect.height * (0.10 + audio * 0.18)
            let x = rect.minX + rect.width * t + drift
            let width = rect.width * (0.045 + audio * 0.05 + (intense ? 0.018 : 0))
            let height = rect.height * (0.72 + audio * 0.42 + energy * 0.22)
            let color = [colors.low, colors.mid, colors.high, colors.spark][fold % 4]
            let alpha = (intense ? 0.07 : 0.045) + audio * 0.10 + energy * 0.05
            let foldPath = CGMutablePath()
            foldPath.move(to: CGPoint(x: x - width, y: rect.midY - height * 0.5))
            foldPath.addLine(to: CGPoint(x: x + width * 0.55, y: rect.midY - height * 0.32 + skew * 0.35))
            foldPath.addLine(to: CGPoint(x: x + width, y: rect.midY + height * 0.5))
            foldPath.addLine(to: CGPoint(x: x - width * 0.55, y: rect.midY + height * 0.32 - skew * 0.35))
            foldPath.closeSubpath()

            context.addPath(foldPath)
            context.setFillColor(color.withAlphaComponent(alpha * 0.45).cgColor)
            context.setShadow(offset: .zero, blur: 12 + audio * 18, color: color.withAlphaComponent(alpha).cgColor)
            context.fillPath()

            context.addPath(foldPath)
            context.setStrokeColor(color.withAlphaComponent(alpha * 0.88).cgColor)
            context.setLineWidth(0.42 + audio * 0.24)
            context.strokePath()
        }

        context.restoreGState()
    }

    private func drawXenoLinks(nodes: [CGPoint], context: CGContext, colors: IndicatorPaletteColors, intense: Bool) {
        guard nodes.count > 1 else { return }
        context.setLineCap(.round)
        context.setLineJoin(.round)
        for index in 0..<(nodes.count - 1) {
            let alpha = intense ? 0.22 + CGFloat(index % 3) * 0.04 : 0.12 + CGFloat(index % 3) * 0.025
            context.setStrokeColor((index.isMultiple(of: 2) ? colors.mid : colors.high).withAlphaComponent(alpha).cgColor)
            context.setLineWidth(intense ? 0.85 : 0.55)
            context.move(to: nodes[index])
            context.addLine(to: nodes[index + 1])
            context.strokePath()
        }

        guard intense else { return }
        for index in stride(from: 0, to: nodes.count - 2, by: 2) {
            context.setStrokeColor(colors.spark.withAlphaComponent(0.12).cgColor)
            context.setLineWidth(0.45)
            context.move(to: nodes[index])
            context.addLine(to: nodes[index + 2])
            context.strokePath()
        }
    }

    private func drawXenoPrismShards(in rect: NSRect, nodes: [CGPoint], context: CGContext, colors: IndicatorPaletteColors, energy: CGFloat, intense: Bool) {
        context.saveGState()
        context.setBlendMode(.plusLighter)
        context.setLineJoin(.miter)
        context.setLineCap(.butt)

        for (index, node) in nodes.enumerated() where index.isMultiple(of: 2) {
            let progress = CGFloat(index) / CGFloat(max(1, nodes.count - 1))
            let audio = mirroredLevel(at: Int(progress * CGFloat(levelCount - 1)))
            let shard = 2.2 + audio * (intense ? 8.0 : 5.2) + energy * 3.0
            let tilt = CGFloat(sin(phase * 1.1 + Float(index))) * shard * 0.45
            let color = index.isMultiple(of: 4) ? colors.spark : colors.high
            let alpha = (intense ? 0.14 : 0.10) + audio * 0.26 + energy * 0.08
            let shardPath = CGMutablePath()
            shardPath.move(to: CGPoint(x: node.x, y: node.y - shard))
            shardPath.addLine(to: CGPoint(x: node.x + shard * 0.42 + tilt, y: node.y))
            shardPath.addLine(to: CGPoint(x: node.x, y: node.y + shard))
            shardPath.addLine(to: CGPoint(x: node.x - shard * 0.42 + tilt * 0.25, y: node.y))
            shardPath.closeSubpath()

            context.addPath(shardPath)
            context.setStrokeColor(color.withAlphaComponent(alpha).cgColor)
            context.setLineWidth(0.45 + audio * 0.38)
            context.setShadow(offset: .zero, blur: 8 + audio * 13, color: color.withAlphaComponent(alpha).cgColor)
            context.strokePath()

            if intense || audio > 0.16 {
                context.setStrokeColor(colors.spark.withAlphaComponent(alpha * 0.72).cgColor)
                context.setLineWidth(0.36 + audio * 0.28)
                context.move(to: CGPoint(x: node.x - shard * 0.72, y: node.y - shard * 0.38))
                context.addLine(to: CGPoint(x: node.x + shard * 0.72, y: node.y + shard * 0.38))
                context.move(to: CGPoint(x: node.x + shard * 0.72, y: node.y - shard * 0.38))
                context.addLine(to: CGPoint(x: node.x - shard * 0.72, y: node.y + shard * 0.38))
                context.strokePath()
            }
        }

        context.restoreGState()
    }

    private func drawXenoNodes(nodes: [CGPoint], context: CGContext, colors: IndicatorPaletteColors, energy: CGFloat) {
        for (index, node) in nodes.enumerated() {
            let pulse = CGFloat(0.5 + 0.5 * sin(phase * 2.1 + Float(index) * 1.7))
            let arm = 1.15 + pulse * 1.15 + energy * 1.6
            let color = index.isMultiple(of: 3) ? colors.spark : (index.isMultiple(of: 2) ? colors.mid : colors.high)
            let alpha = 0.32 + pulse * 0.34 + energy * 0.18
            context.setShadow(offset: .zero, blur: 6 + pulse * 5, color: color.withAlphaComponent(alpha).cgColor)
            context.setStrokeColor(color.withAlphaComponent(alpha).cgColor)
            context.setLineWidth(0.6 + pulse * 0.4)
            context.setLineCap(.round)

            if index % 3 == 0 {
                context.move(to: CGPoint(x: node.x - arm, y: node.y))
                context.addLine(to: CGPoint(x: node.x + arm, y: node.y))
                context.move(to: CGPoint(x: node.x, y: node.y - arm))
                context.addLine(to: CGPoint(x: node.x, y: node.y + arm))
            } else if index % 3 == 1 {
                let d = arm * 0.8
                context.move(to: CGPoint(x: node.x, y: node.y - d))
                context.addLine(to: CGPoint(x: node.x + d * 0.6, y: node.y))
                context.addLine(to: CGPoint(x: node.x, y: node.y + d))
                context.addLine(to: CGPoint(x: node.x - d * 0.6, y: node.y))
                context.addLine(to: CGPoint(x: node.x, y: node.y - d))
            } else {
                let d = arm * 0.72
                context.move(to: CGPoint(x: node.x - d, y: node.y - d))
                context.addLine(to: CGPoint(x: node.x + d, y: node.y + d))
                context.move(to: CGPoint(x: node.x + d, y: node.y - d))
                context.addLine(to: CGPoint(x: node.x - d, y: node.y + d))
            }
            context.strokePath()
        }
    }

    private func drawXenoListeningField(in rect: NSRect, context: CGContext, colors: IndicatorPaletteColors, energy: CGFloat) {
        let gate = CGFloat(0.5 + 0.5 * sin(phase * 0.56))
        let gateX = rect.minX + rect.width * gate
        let gateRect = NSRect(x: gateX - rect.width * 0.12, y: rect.minY - 4, width: rect.width * 0.24, height: rect.height + 8)
        drawLinearGradient(
            in: gateRect,
            context: context,
            colors: [colors.low.withAlphaComponent(0), colors.mid.withAlphaComponent(0.08 + energy * 0.12), colors.high.withAlphaComponent(0)],
            locations: [0, 0.5, 1],
            start: CGPoint(x: gateRect.minX, y: gateRect.midY),
            end: CGPoint(x: gateRect.maxX, y: gateRect.midY)
        )

        let coreRadius = rect.height * (0.10 + energy * 0.20)
        let d = coreRadius * 1.2
        context.setShadow(offset: .zero, blur: 11, color: colors.mid.withAlphaComponent(0.36).cgColor)
        context.setStrokeColor(colors.spark.withAlphaComponent(0.26 + energy * 0.22).cgColor)
        context.setLineWidth(0.75)
        context.move(to: CGPoint(x: rect.midX, y: rect.midY - d))
        context.addLine(to: CGPoint(x: rect.midX + d * 0.6, y: rect.midY))
        context.addLine(to: CGPoint(x: rect.midX, y: rect.midY + d))
        context.addLine(to: CGPoint(x: rect.midX - d * 0.6, y: rect.midY))
        context.addLine(to: CGPoint(x: rect.midX, y: rect.midY - d))
        context.strokePath()
    }

    private func drawXenoVoiceBursts(in rect: NSRect, nodes: [CGPoint], context: CGContext, colors: IndicatorPaletteColors, energy: CGFloat) {
        let globalBurst = max(0, min(1, (energy - 0.035) / 0.28))
        guard globalBurst > 0.02 || nodes.contains(where: { node in
            let progress = max(0, min(1, (node.x - rect.minX) / max(1, rect.width)))
            return mirroredLevel(at: Int(progress * CGFloat(levelCount - 1))) > 0.08
        }) else { return }

        for (index, node) in nodes.enumerated() {
            let progress = CGFloat(index) / CGFloat(max(1, nodes.count - 1))
            let audio = mirroredLevel(at: Int(progress * CGFloat(levelCount - 1)))
            let localBurst = max(0, min(1, (audio - 0.055) / 0.58))
            let flicker = 0.58 + 0.42 * CGFloat(sin(phase * 6.2 + Float(index) * 2.39))
            let burst = max(globalBurst * 0.42, localBurst) * flicker
            guard burst > 0.045 else { continue }

            let haloRadius = 4.0 + burst * 16.0
            let color = index.isMultiple(of: 2) ? colors.spark : colors.mid
            context.setShadow(offset: .zero, blur: 10 + burst * 18, color: color.withAlphaComponent(0.34 + burst * 0.36).cgColor)
            context.setStrokeColor(color.withAlphaComponent(0.20 + burst * 0.42).cgColor)
            context.setLineWidth(0.55 + burst * 0.65)
            let hd = haloRadius * 0.6
            context.move(to: CGPoint(x: node.x, y: node.y - hd))
            context.addLine(to: CGPoint(x: node.x + hd * 0.6, y: node.y))
            context.addLine(to: CGPoint(x: node.x, y: node.y + hd))
            context.addLine(to: CGPoint(x: node.x - hd * 0.6, y: node.y))
            context.addLine(to: CGPoint(x: node.x, y: node.y - hd))
            context.strokePath()

            let flashArm = 1.0 + burst * 4.2
            context.setStrokeColor(color.withAlphaComponent(0.34 + burst * 0.46).cgColor)
            context.setLineWidth(0.5 + burst * 0.3)
            context.move(to: CGPoint(x: node.x - flashArm, y: node.y))
            context.addLine(to: CGPoint(x: node.x + flashArm, y: node.y))
            context.move(to: CGPoint(x: node.x, y: node.y - flashArm))
            context.addLine(to: CGPoint(x: node.x, y: node.y + flashArm))
            context.strokePath()

            for spoke in 0..<4 {
                let angle = phase * 1.8 + Float(index) * 0.73 + Float(spoke) * (.pi / 2)
                let length = 5.0 + burst * 13.0
                let dx = CGFloat(cos(angle)) * length
                let dy = CGFloat(sin(angle)) * length * 0.52
                context.setStrokeColor((spoke.isMultiple(of: 2) ? colors.high : colors.spark).withAlphaComponent(0.12 + burst * 0.28).cgColor)
                context.setLineWidth(0.45 + burst * 0.35)
                context.move(to: CGPoint(x: node.x - dx * 0.25, y: node.y - dy * 0.25))
                context.addLine(to: CGPoint(x: node.x + dx, y: node.y + dy))
                context.strokePath()
            }
        }

        let centralFlash = max(0, min(1, (energy - 0.08) / 0.35))
        guard centralFlash > 0.03 else { return }
        let d = rect.height * (0.24 + centralFlash * 0.42)
        context.setShadow(offset: .zero, blur: 22, color: colors.spark.withAlphaComponent(0.30 + centralFlash * 0.38).cgColor)
        context.setStrokeColor(colors.mid.withAlphaComponent(0.05 + centralFlash * 0.16).cgColor)
        context.setLineWidth(0.7 + centralFlash * 0.5)
        context.move(to: CGPoint(x: rect.midX, y: rect.midY - d))
        context.addLine(to: CGPoint(x: rect.midX + d * 0.6, y: rect.midY))
        context.addLine(to: CGPoint(x: rect.midX, y: rect.midY + d))
        context.addLine(to: CGPoint(x: rect.midX - d * 0.6, y: rect.midY))
        context.addLine(to: CGPoint(x: rect.midX, y: rect.midY - d))
        context.strokePath()
    }

    private func drawXenoComputationField(in rect: NSRect, nodes: [CGPoint], context: CGContext, colors: IndicatorPaletteColors, energy: CGFloat) {
        let pulse = CGFloat(0.5 + 0.5 * sin(phase * 2.35))
        let burst = CGFloat(pow(Double(max(0, sin(phase * 0.71 + sin(phase * 1.9)))), 2.4))
        let diamondWidth = rect.width * (0.16 + pulse * 0.04 + burst * 0.06)
        let diamondHeight = rect.height * (0.42 + energy * 0.38 + burst * 0.20)
        let diamond = CGMutablePath()
        diamond.move(to: CGPoint(x: rect.midX, y: rect.midY + diamondHeight))
        diamond.addLine(to: CGPoint(x: rect.midX + diamondWidth, y: rect.midY))
        diamond.addLine(to: CGPoint(x: rect.midX, y: rect.midY - diamondHeight))
        diamond.addLine(to: CGPoint(x: rect.midX - diamondWidth, y: rect.midY))
        diamond.closeSubpath()

        context.setShadow(offset: .zero, blur: 14 + burst * 10, color: colors.mid.withAlphaComponent(0.58).cgColor)
        context.addPath(diamond)
        context.setStrokeColor(colors.spark.withAlphaComponent(0.42 + burst * 0.34).cgColor)
        context.setLineWidth(0.9 + pulse * 0.5)
        context.strokePath()

        for node in nodes where abs(node.x - rect.midX) > rect.width * 0.18 {
            context.setStrokeColor(colors.mid.withAlphaComponent(0.08 + burst * 0.08).cgColor)
            context.setLineWidth(0.38)
            context.move(to: node)
            context.addLine(to: CGPoint(x: rect.midX, y: rect.midY))
            context.strokePath()
        }

        for offset in [-0.18, 0.18] as [CGFloat] {
            let slitX = rect.midX + rect.width * offset * CGFloat(sin(phase * 0.84))
            let slitRect = NSRect(x: slitX - 1, y: rect.minY - 4, width: 2, height: rect.height + 8)
            context.setFillColor(colors.high.withAlphaComponent(0.20 + burst * 0.28).cgColor)
            context.fill(slitRect)
        }
    }

    private func drawXenoLockShards(in rect: NSRect, nodes: [CGPoint], context: CGContext, colors: IndicatorPaletteColors, energy: CGFloat) {
        let pulse = CGFloat(0.5 + 0.5 * sin(phase * 1.72))
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let cageWidth = rect.width * (0.18 + pulse * 0.03 + energy * 0.04)
        let cageHeight = rect.height * (0.46 + pulse * 0.10 + energy * 0.16)

        context.saveGState()
        context.setBlendMode(.plusLighter)
        context.setLineJoin(.miter)
        context.setLineCap(.butt)
        context.setShadow(offset: .zero, blur: 16 + energy * 18, color: colors.spark.withAlphaComponent(0.34 + energy * 0.18).cgColor)
        context.setStrokeColor(colors.spark.withAlphaComponent(0.28 + pulse * 0.18 + energy * 0.18).cgColor)
        context.setLineWidth(0.75 + pulse * 0.34)

        for scale in [1.0, 1.34, 1.72] as [CGFloat] {
            let w = cageWidth * scale
            let h = cageHeight * scale
            context.move(to: CGPoint(x: center.x, y: center.y - h))
            context.addLine(to: CGPoint(x: center.x + w * 0.62, y: center.y))
            context.addLine(to: CGPoint(x: center.x, y: center.y + h))
            context.addLine(to: CGPoint(x: center.x - w * 0.62, y: center.y))
            context.addLine(to: CGPoint(x: center.x, y: center.y - h))
            context.strokePath()
        }

        for node in nodes where abs(node.x - center.x) > rect.width * 0.16 {
            context.setStrokeColor(colors.mid.withAlphaComponent(0.10 + energy * 0.10).cgColor)
            context.setLineWidth(0.42)
            context.move(to: node)
            context.addLine(to: center)
            context.strokePath()
        }

        context.restoreGState()
    }

    // MARK: - Shared Helpers

    private func fill(_ path: CGPath, context: CGContext, colors: [NSColor]) {
        let bounds = path.boundingBoxOfPath
        context.saveGState()
        context.setBlendMode(.plusLighter)
        context.addPath(path)
        context.clip()
        drawLinearGradient(
            in: bounds,
            context: context,
            colors: colors,
            locations: [0, 0.5, 1],
            start: CGPoint(x: bounds.minX, y: bounds.midY),
            end: CGPoint(x: bounds.maxX, y: bounds.midY)
        )
        context.restoreGState()
    }

    private func stroke(_ path: CGPath, context: CGContext, color: NSColor, width: CGFloat, blur: CGFloat) {
        context.saveGState()
        context.setBlendMode(.plusLighter)
        context.setLineJoin(.round)
        context.setLineCap(.round)
        context.setShadow(offset: .zero, blur: blur, color: color.cgColor)
        context.addPath(path)
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(width)
        context.strokePath()
        context.restoreGState()
    }

    private func drawCenterFilament(in rect: NSRect, context: CGContext, color: NSColor, width: CGFloat) {
        context.saveGState()
        context.setBlendMode(.plusLighter)
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(width)
        context.setLineCap(.round)
        context.setShadow(offset: .zero, blur: 4, color: color.cgColor)
        context.move(to: CGPoint(x: rect.minX, y: rect.midY))
        context.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        context.strokePath()
        context.restoreGState()
    }

    private func drawMicroTicks(in rect: NSRect, context: CGContext, color: NSColor, density: Int, heightScale: CGFloat) {
        guard density > 1 else { return }
        context.saveGState()
        context.setBlendMode(.plusLighter)
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(0.8)
        context.setLineCap(.round)
        for i in 0..<density {
            let xProgress = CGFloat(i) / CGFloat(density - 1)
            let index = Int(xProgress * CGFloat(levelCount - 1))
            let level = mirroredLevel(at: index)
            let x = rect.minX + rect.width * xProgress
            let h = max(2, rect.height * (0.05 + level * heightScale))
            context.move(to: CGPoint(x: x, y: rect.midY - h * 0.5))
            context.addLine(to: CGPoint(x: x, y: rect.midY + h * 0.5))
        }
        context.strokePath()
        context.restoreGState()
    }

    private func drawScanBloom(in rect: NSRect, context: CGContext, color: NSColor, width: CGFloat) {
        let travel = CGFloat(0.5 + 0.5 * sin(phase * 0.92))
        let x = rect.minX + rect.width * travel
        let scanRect = NSRect(x: x - width * 0.5, y: rect.minY - 2, width: width, height: rect.height + 4)
        context.saveGState()
        context.setBlendMode(.plusLighter)
        context.clip(to: scanRect)
        drawLinearGradient(
            in: scanRect,
            context: context,
            colors: [color.withAlphaComponent(0), color, color.withAlphaComponent(0)],
            locations: [0, 0.5, 1],
            start: CGPoint(x: scanRect.minX, y: scanRect.midY),
            end: CGPoint(x: scanRect.maxX, y: scanRect.midY)
        )
        context.restoreGState()
    }

    private func drawSignalGlassListeningSweep(in rect: NSRect, context: CGContext, color: NSColor, spark: NSColor) {
        let travel = CGFloat(0.5 + 0.5 * sin(phase * 0.48))
        let x = rect.minX + rect.width * travel
        let alphaBoost = min(0.10, averageLevel() * 0.12)
        let clipRect = rect.insetBy(dx: -8, dy: -4)

        context.saveGState()
        context.setBlendMode(.plusLighter)
        context.clip(to: clipRect)

        let washRect = NSRect(x: x - 13, y: rect.minY - 2, width: 26, height: rect.height + 4)
        drawLinearGradient(
            in: washRect,
            context: context,
            colors: [color.withAlphaComponent(0), color.withAlphaComponent(0.08 + alphaBoost), color.withAlphaComponent(0)],
            locations: [0, 0.5, 1],
            start: CGPoint(x: washRect.minX, y: washRect.midY),
            end: CGPoint(x: washRect.maxX, y: washRect.midY)
        )

        for offset in [-3.2, 3.2] as [CGFloat] {
            let beamRect = NSRect(x: x + offset - 0.45, y: rect.minY, width: 0.9, height: rect.height)
            context.setShadow(offset: .zero, blur: 3, color: color.withAlphaComponent(0.18 + alphaBoost).cgColor)
            context.setFillColor((offset < 0 ? color : spark).withAlphaComponent(0.16 + alphaBoost).cgColor)
            context.fill(beamRect)
        }

        context.restoreGState()
    }

    private func drawLiquidListeningGlints(in rect: NSRect, context: CGContext, colors: IndicatorPaletteColors) {
        let orbit = CGFloat(0.5 + 0.5 * sin(phase * 0.62))
        let counterOrbit = CGFloat(0.5 + 0.5 * sin(phase * 0.62 + Float.pi))
        let energy = averageLevel()

        context.saveGState()
        context.setBlendMode(.plusLighter)
        context.clip(to: rect.insetBy(dx: -12, dy: -7))

        for (index, progress) in [orbit, counterOrbit].enumerated() {
            let x = rect.minX + rect.width * progress
            let wobble = CGFloat(sin(phase * (1.4 + Float(index) * 0.35))) * 2.6
            let y = rect.midY + (index == 0 ? wobble : -wobble)
            let radius = 1.8 + energy * 2.8 + CGFloat(index) * 0.6
            let causticRect = NSRect(x: x - 28, y: rect.minY - 3, width: 56, height: rect.height + 6)

            drawLinearGradient(
                in: causticRect,
                context: context,
                colors: [colors.low.withAlphaComponent(0), colors.mid.withAlphaComponent(0.09 + energy * 0.10), colors.high.withAlphaComponent(0)],
                locations: [0, 0.5, 1],
                start: CGPoint(x: causticRect.minX, y: causticRect.midY),
                end: CGPoint(x: causticRect.maxX, y: causticRect.midY)
            )

            let glintRect = NSRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
            context.setShadow(offset: .zero, blur: 9, color: colors.mid.withAlphaComponent(0.45).cgColor)
            context.setFillColor((index == 0 ? colors.spark : colors.high).withAlphaComponent(0.38 + energy * 0.24).cgColor)
            context.fillEllipse(in: glintRect)
        }

        context.restoreGState()
    }

    private func drawAuroraListeningCurtain(in rect: NSRect, context: CGContext, colors: IndicatorPaletteColors) {
        let energy = averageLevel()
        let pulse = CGFloat(0.5 + 0.5 * sin(phase * 0.44 + sin(phase * 0.21)))
        let sheetRect = rect.insetBy(dx: -14, dy: -7)

        context.saveGState()
        context.setBlendMode(.plusLighter)
        context.clip(to: sheetRect)

        drawLinearGradient(
            in: sheetRect,
            context: context,
            colors: [colors.low.withAlphaComponent(0.02), colors.mid.withAlphaComponent(0.06 + pulse * 0.10 + energy * 0.10), colors.high.withAlphaComponent(0.02)],
            locations: [0, 0.48, 1],
            start: CGPoint(x: sheetRect.minX, y: sheetRect.midY),
            end: CGPoint(x: sheetRect.maxX, y: sheetRect.midY)
        )

        for band in 0..<3 {
            let progress = CGFloat(0.5 + 0.5 * sin(phase * (0.33 + Float(band) * 0.09) + Float(band) * 1.7))
            let x = rect.minX + rect.width * progress
            let width = rect.width * (0.14 + CGFloat(band) * 0.035)
            let curtainRect = NSRect(x: x - width / 2, y: rect.minY - 6, width: width, height: rect.height + 12)
            let color = [colors.low, colors.mid, colors.high][band]
            drawLinearGradient(
                in: curtainRect,
                context: context,
                colors: [color.withAlphaComponent(0), color.withAlphaComponent(0.08 + pulse * 0.08), color.withAlphaComponent(0)],
                locations: [0, 0.5, 1],
                start: CGPoint(x: curtainRect.minX, y: curtainRect.midY),
                end: CGPoint(x: curtainRect.maxX, y: curtainRect.midY)
            )
        }

        context.restoreGState()
    }

    private func drawPrismScanner(in rect: NSRect, context: CGContext, color: NSColor, spark: NSColor) {
        let cycle = CGFloat((phase * 0.18).truncatingRemainder(dividingBy: 1))
        let x = rect.minX + rect.width * cycle
        let clipRect = rect.insetBy(dx: -10, dy: -4)

        context.saveGState()
        context.setBlendMode(.plusLighter)
        context.clip(to: clipRect)

        let washRect = NSRect(x: x - 24, y: rect.minY - 3, width: 48, height: rect.height + 6)
        drawLinearGradient(
            in: washRect,
            context: context,
            colors: [color.withAlphaComponent(0), color.withAlphaComponent(0.24), spark.withAlphaComponent(0)],
            locations: [0, 0.52, 1],
            start: CGPoint(x: washRect.minX, y: washRect.midY),
            end: CGPoint(x: washRect.maxX, y: washRect.midY)
        )

        for beam in 0..<3 {
            let offset = CGFloat(beam - 1) * 7.0
            let alpha = beam == 1 ? 0.64 : 0.28
            let beamRect = NSRect(x: x + offset - 1.15, y: rect.minY - 2, width: 2.3, height: rect.height + 4)
            context.setShadow(offset: .zero, blur: beam == 1 ? 8 : 4, color: color.withAlphaComponent(alpha).cgColor)
            context.setFillColor((beam == 1 ? spark : color).withAlphaComponent(alpha).cgColor)
            context.fill(beamRect)
        }

        context.restoreGState()
    }

    private func drawNeonComet(in rect: NSRect, context: CGContext, colors: IndicatorPaletteColors) {
        let cycle = CGFloat((phase * 0.22).truncatingRemainder(dividingBy: 1))
        let x = rect.minX + rect.width * cycle
        let y = rect.midY + CGFloat(sin(phase * 1.35)) * 2.2
        let trailWidth: CGFloat = 86
        let trailRect = NSRect(x: x - trailWidth, y: rect.minY - 5, width: trailWidth + 30, height: rect.height + 10)

        context.saveGState()
        context.setBlendMode(.plusLighter)
        context.clip(to: rect.insetBy(dx: -12, dy: -8))
        drawLinearGradient(
            in: trailRect,
            context: context,
            colors: [colors.low.withAlphaComponent(0), colors.mid.withAlphaComponent(0.10), colors.spark.withAlphaComponent(0.32)],
            locations: [0, 0.72, 1],
            start: CGPoint(x: trailRect.minX, y: trailRect.midY),
            end: CGPoint(x: trailRect.maxX, y: trailRect.midY)
        )

        let headRadius: CGFloat = 4.8 + CGFloat(0.5 + 0.5 * sin(phase * 2.4)) * 2.2
        let headRect = NSRect(x: x - headRadius, y: y - headRadius, width: headRadius * 2, height: headRadius * 2)
        context.setShadow(offset: .zero, blur: 12, color: colors.mid.withAlphaComponent(0.48).cgColor)
        context.setFillColor(colors.spark.withAlphaComponent(0.42).cgColor)
        context.fillEllipse(in: headRect)

        for ring in 0..<2 {
            let ringRadius = headRadius + CGFloat(ring + 1) * 4.8 + CGFloat(0.5 + 0.5 * sin(phase * 2.1 + Float(ring))) * 3.0
            let hd = ringRadius * 0.5
            context.setStrokeColor((ring == 0 ? colors.spark : colors.high).withAlphaComponent(0.16 - CGFloat(ring) * 0.05).cgColor)
            context.setLineWidth(0.65)
            context.move(to: CGPoint(x: x, y: y - hd))
            context.addLine(to: CGPoint(x: x + hd * 0.6, y: y))
            context.addLine(to: CGPoint(x: x, y: y + hd))
            context.addLine(to: CGPoint(x: x - hd * 0.6, y: y))
            context.addLine(to: CGPoint(x: x, y: y - hd))
            context.strokePath()
        }

        for sparkIndex in 0..<4 {
            let t = CGFloat(sparkIndex) / 3
            let sparkX = x - 18 - t * 52
            let sparkY = y + CGFloat(sin(phase * 3.1 + Float(sparkIndex))) * 3
            let arm = 0.7 + CGFloat(sparkIndex % 2) * 0.45
            context.setStrokeColor(colors.high.withAlphaComponent(0.18 - t * 0.08).cgColor)
            context.setLineWidth(0.4)
            context.move(to: CGPoint(x: sparkX - arm, y: sparkY))
            context.addLine(to: CGPoint(x: sparkX + arm, y: sparkY))
            context.move(to: CGPoint(x: sparkX, y: sparkY - arm))
            context.addLine(to: CGPoint(x: sparkX, y: sparkY + arm))
            context.strokePath()
        }
        context.restoreGState()
    }

    private func drawAuroraThrob(in rect: NSRect, context: CGContext, colors: IndicatorPaletteColors) {
        let irregular = max(0, CGFloat(sin(phase * 0.77) + 0.34 * sin(phase * 2.13 + 1.1)))
        let pulse = min(1, 0.18 + pow(irregular, 3.2) * 0.82 + CGFloat(0.5 + 0.5 * sin(phase * 0.31)) * 0.16)
        let haloWidth = rect.width * (0.40 + pulse * 0.42)
        let haloHeight = rect.height * (1.25 + pulse * 1.2)
        let haloRect = NSRect(x: rect.midX - haloWidth / 2, y: rect.midY - haloHeight / 2, width: haloWidth, height: haloHeight)

        context.saveGState()
        context.setBlendMode(.plusLighter)
        context.clip(to: rect.insetBy(dx: -18, dy: -10))
        context.setShadow(offset: .zero, blur: 18 + pulse * 20, color: colors.mid.withAlphaComponent(0.42 + pulse * 0.32).cgColor)
        context.setFillColor(colors.mid.withAlphaComponent(0.10 + pulse * 0.24).cgColor)
        context.fillEllipse(in: haloRect)

        let sheetRect = rect.insetBy(dx: -12, dy: -7)
        drawLinearGradient(
            in: sheetRect,
            context: context,
            colors: [colors.low.withAlphaComponent(0.02), colors.spark.withAlphaComponent(0.08 + pulse * 0.20), colors.high.withAlphaComponent(0.02)],
            locations: [0, 0.5, 1],
            start: CGPoint(x: sheetRect.midX, y: sheetRect.maxY),
            end: CGPoint(x: sheetRect.midX, y: sheetRect.minY)
        )

        for filament in 0..<5 {
            let t = CGFloat(filament) / 4
            let drift = CGFloat(sin(phase * (0.42 + Float(filament) * 0.07) + Float(filament) * 1.9)) * 10
            let x = rect.minX + rect.width * t + drift
            let height = rect.height * (0.35 + pulse * 0.45 + CGFloat(filament % 2) * 0.10)
            context.setStrokeColor([colors.low, colors.mid, colors.high, colors.spark, colors.mid][filament].withAlphaComponent(0.10 + pulse * 0.18).cgColor)
            context.setLineWidth(0.7 + pulse * 0.5)
            context.setShadow(offset: .zero, blur: 8 + pulse * 10, color: colors.mid.withAlphaComponent(0.24 + pulse * 0.22).cgColor)
            context.move(to: CGPoint(x: x, y: rect.midY - height * 0.5))
            context.addLine(to: CGPoint(x: x + drift * 0.10, y: rect.midY + height * 0.5))
            context.strokePath()
        }
        context.restoreGState()
    }

    private func drawInterferenceLines(in rect: NSRect, context: CGContext, colors: [NSColor]) {
        context.saveGState()
        context.setBlendMode(.plusLighter)
        context.setLineCap(.round)
        for band in 0..<5 {
            let color = colors[band % colors.count].withAlphaComponent(0.15 + CGFloat(band) * 0.035)
            let yOffset = (CGFloat(band) - 2) * 3.1
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(0.55 + CGFloat(band) * 0.12)
            context.beginPath()
            for step in 0..<36 {
                let t = CGFloat(step) / 35
                let ripple = CGFloat(sin(phase * (1.1 + Float(band) * 0.18) + Float(t) * 22 + Float(band)))
                let energy = mirroredLevel(at: Int(t * CGFloat(levelCount - 1)))
                let point = CGPoint(x: rect.minX + rect.width * t,
                                    y: rect.midY + yOffset + ripple * (1.4 + energy * 4.8))
                if step == 0 {
                    context.move(to: point)
                } else {
                    context.addLine(to: point)
                }
            }
            context.strokePath()
        }
        context.restoreGState()
    }

    private func drawOriginalUFOReactorCore(in rect: NSRect, context: CGContext, color: NSColor) {
        let energy = max(0.14, averageLevel())
        let pulse = CGFloat(0.5 + 0.5 * sin(phase * 2.6))
        let radius = min(rect.height * 0.46, 4.5 + energy * 12 + pulse * 2.5)
        let coreRect = NSRect(x: rect.midX - radius, y: rect.midY - radius, width: radius * 2, height: radius * 2)

        context.saveGState()
        context.setBlendMode(.plusLighter)
        context.setShadow(offset: .zero, blur: 18, color: color.withAlphaComponent(0.95).cgColor)
        let corePath = CGPath(ellipseIn: coreRect, transform: nil)
        context.addPath(corePath)
        context.setFillColor(color.withAlphaComponent(0.34).cgColor)
        context.fillPath()
        context.addEllipse(in: coreRect.insetBy(dx: radius * 0.38, dy: radius * 0.38))
        context.setFillColor(NSColor.white.withAlphaComponent(0.88).cgColor)
        context.fillPath()
        context.restoreGState()
    }

    private func drawOriginalUFOParticles(in rect: NSRect, context: CGContext, color: NSColor, threshold: CGFloat, count: Int) {
        guard count > 0 else { return }
        context.saveGState()
        context.setBlendMode(.plusLighter)
        context.setShadow(offset: .zero, blur: 5, color: color.cgColor)
        for i in 0..<count {
            let t = CGFloat(i) / CGFloat(max(1, count - 1))
            let index = Int(t * CGFloat(levelCount - 1))
            let energy = mirroredLevel(at: index)
            let burst = max(0, (energy - threshold) / max(0.001, 1 - threshold))
            let orbital = CGFloat(sin(phase * 4.3 + Float(i) * 1.618))
            let alpha = min(0.9, 0.10 + burst * 0.72) * (0.55 + 0.45 * abs(orbital))
            guard alpha > 0.12 else { continue }
            let ySign: CGFloat = i.isMultiple(of: 2) ? 1 : -1
            let x = rect.minX + rect.width * t
            let y = rect.midY + ySign * (rect.height * (0.18 + energy * 0.34) + orbital * 2.4)
            let radius = 0.8 + burst * 2.1 + abs(orbital) * 0.45
            let particleRect = NSRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
            context.setFillColor(color.withAlphaComponent(alpha).cgColor)
            context.fillEllipse(in: particleRect)
        }
        context.restoreGState()
    }

    private func drawParticles(in rect: NSRect, context: CGContext, color: NSColor, threshold: CGFloat, count: Int) {
        guard count > 0 else { return }
        context.saveGState()
        context.setBlendMode(.plusLighter)
        context.setLineCap(.round)
        for i in 0..<count {
            let t = CGFloat(i) / CGFloat(max(1, count - 1))
            let index = Int(t * CGFloat(levelCount - 1))
            let energy = mirroredLevel(at: index)
            let burst = max(0, (energy - threshold) / max(0.001, 1 - threshold))
            let orbital = CGFloat(sin(phase * 4.3 + Float(i) * 1.618))
            let alpha = min(0.9, 0.10 + burst * 0.72) * (0.55 + 0.45 * abs(orbital))
            guard alpha > 0.12 else { continue }
            let ySign: CGFloat = i.isMultiple(of: 2) ? 1 : -1
            let x = rect.minX + rect.width * t
            let y = rect.midY + ySign * (rect.height * (0.18 + energy * 0.34) + orbital * 2.4)
            let arm = 0.7 + burst * 2.1 + abs(orbital) * 0.45
            let lineWidth = 0.45 + burst * 0.35

            context.setShadow(offset: .zero, blur: 4 + burst * 4, color: color.withAlphaComponent(alpha).cgColor)
            context.setStrokeColor(color.withAlphaComponent(alpha).cgColor)
            context.setLineWidth(lineWidth)

            if i % 3 == 0 {
                context.move(to: CGPoint(x: x - arm, y: y))
                context.addLine(to: CGPoint(x: x + arm, y: y))
                context.move(to: CGPoint(x: x, y: y - arm))
                context.addLine(to: CGPoint(x: x, y: y + arm))
            } else if i % 3 == 1 {
                let d = arm * 0.72
                context.move(to: CGPoint(x: x - d, y: y - d))
                context.addLine(to: CGPoint(x: x + d, y: y + d))
                context.move(to: CGPoint(x: x + d, y: y - d))
                context.addLine(to: CGPoint(x: x - d, y: y + d))
            } else {
                let angle = phase * 1.1 + Float(i) * 0.9
                let dx = CGFloat(cos(angle)) * arm
                let dy = CGFloat(sin(angle)) * arm * 0.5
                context.move(to: CGPoint(x: x - dx, y: y - dy))
                context.addLine(to: CGPoint(x: x + dx, y: y + dy))
            }
            context.strokePath()
        }
        context.restoreGState()
    }

    private func strokeTemporalArc(center: CGPoint, radiusX: CGFloat, radiusY: CGFloat, start: CGFloat, end: CGFloat, context: CGContext) {
        context.saveGState()
        context.translateBy(x: center.x, y: center.y)
        context.scaleBy(x: 1, y: radiusY / max(0.001, radiusX))
        context.addArc(center: .zero, radius: radiusX, startAngle: start, endAngle: end, clockwise: false)
        context.strokePath()
        context.restoreGState()
    }

    private func drawRadialGradient(in rect: NSRect, context: CGContext, colors: [NSColor], locations: [CGFloat], center: CGPoint? = nil) {
        guard colors.count == locations.count,
              let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors.map { $0.cgColor } as CFArray, locations: locations) else {
            return
        }
        let resolvedCenter = center ?? CGPoint(x: rect.midX, y: rect.midY)
        let radius = max(rect.width, rect.height) * 0.56
        context.drawRadialGradient(
            gradient,
            startCenter: resolvedCenter,
            startRadius: 0,
            endCenter: resolvedCenter,
            endRadius: radius,
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
    }

    private func drawLinearGradient(in rect: NSRect, context: CGContext, colors: [NSColor], locations: [CGFloat], start: CGPoint, end: CGPoint) {
        guard colors.count == locations.count,
              let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors.map { $0.cgColor } as CFArray, locations: locations) else {
            return
        }
        context.drawLinearGradient(gradient, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }
}
