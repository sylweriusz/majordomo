import AppKit
import MajordomoCore

// Settings model for the dictation indicator: the visual style, on-screen
// placement, and color palette. Extracted from WaveformOverlayView so the view
// file holds only rendering, and these persisted enums live on their own.

enum IndicatorVisualStyle: String, CaseIterable {
    case signalGlass
    case liquidNeon
    case auroraPlasma
    case nebulaEngine
    case temporalRift
    case crystalLens
    case cosmicStorm
    case neuralNetwork
    case plasmaVortex
    case ufoReactor
    case xenoLattice
    case unicornSparklepop

    static let userDefaultsKey = DefaultsKey.indicatorVisualStyle
    static let defaultStyle: IndicatorVisualStyle = .liquidNeon

    var displayName: String {
        switch self {
        case .signalGlass: "Signal Glass"
        case .liquidNeon: "Liquid Neon"
        case .auroraPlasma: "Aurora Plasma"
        case .nebulaEngine: "Nebula Engine"
        case .temporalRift: "Temporal Rift"
        case .crystalLens: "Crystal Lens"
        case .cosmicStorm: "Cosmic Storm"
        case .neuralNetwork: "Neural Network"
        case .plasmaVortex: "Plasma Vortex"
        case .ufoReactor: "UFO Reactor"
        case .xenoLattice: "Xeno Lattice"
        case .unicornSparklepop: "Unicorn Sparklepop"
        }
    }

    static func load(from defaults: UserDefaults = .standard) -> IndicatorVisualStyle {
        guard let rawValue = defaults.string(forKey: userDefaultsKey),
              let style = IndicatorVisualStyle(rawValue: rawValue) else {
            return defaultStyle
        }
        return style
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.userDefaultsKey)
    }
}

enum IndicatorPlacement: String, CaseIterable {
    case auto
    case notch
    case dockWings

    static let userDefaultsKey = DefaultsKey.indicatorPlacement
    static let defaultPlacement: IndicatorPlacement = .auto

    var displayName: String {
        switch self {
        case .auto: "Auto"
        case .notch: "Notch Capsule"
        case .dockWings: "Dock Wings"
        }
    }

    static func load(from defaults: UserDefaults = .standard) -> IndicatorPlacement {
        guard let rawValue = defaults.string(forKey: userDefaultsKey),
              let placement = IndicatorPlacement(rawValue: rawValue) else {
            return defaultPlacement
        }
        return placement
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.userDefaultsKey)
    }
}

enum IndicatorColorPalette: String, CaseIterable {
    case oceanic
    case ultraviolet
    case solarFlare
    case roseGold
    case arcticGhost
    case acidMatrix
    case voidGold
    case deepSpace
    case toxicMist
    case bloodMoon
    case neonPulse
    case cottonCandyKisses

    static let userDefaultsKey = DefaultsKey.indicatorColorPalette
    static let defaultPalette: IndicatorColorPalette = .oceanic

    var displayName: String {
        switch self {
        case .oceanic: "Oceanic"
        case .ultraviolet: "Ultraviolet"
        case .solarFlare: "Solar Flare"
        case .roseGold: "Rose Gold"
        case .arcticGhost: "Arctic Ghost"
        case .acidMatrix: "Acid Matrix"
        case .voidGold: "Void Gold"
        case .deepSpace: "Deep Space"
        case .toxicMist: "Toxic Mist"
        case .bloodMoon: "Blood Moon"
        case .neonPulse: "Neon Pulse"
        case .cottonCandyKisses: "Cotton Candy Kisses"
        }
    }

    static func load(from defaults: UserDefaults = .standard) -> IndicatorColorPalette {
        guard let rawValue = defaults.string(forKey: userDefaultsKey),
              let palette = IndicatorColorPalette(rawValue: rawValue) else {
            return defaultPalette
        }
        return palette
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.userDefaultsKey)
    }

    func colors(for mode: WaveformOverlayMode) -> IndicatorPaletteColors {
        switch (self, mode) {
        case (.oceanic, .recording):
            IndicatorPaletteColors(low: Self.color(0.08, 0.32, 1.00), mid: Self.color(0.25, 0.96, 1.00), high: Self.color(0.56, 0.36, 1.00), spark: NSColor.white)
        case (.oceanic, .transcribing):
            IndicatorPaletteColors(low: Self.color(0.46, 0.22, 1.00), mid: Self.color(0.96, 0.34, 1.00), high: Self.color(0.24, 0.78, 1.00), spark: NSColor.white)
        case (.ultraviolet, .recording):
            IndicatorPaletteColors(low: Self.color(0.20, 0.05, 0.78), mid: Self.color(0.78, 0.20, 1.00), high: Self.color(0.16, 0.94, 1.00), spark: Self.color(0.94, 0.86, 1.00))
        case (.ultraviolet, .transcribing):
            IndicatorPaletteColors(low: Self.color(0.42, 0.05, 0.92), mid: Self.color(1.00, 0.16, 0.74), high: Self.color(0.42, 0.72, 1.00), spark: Self.color(1.00, 0.92, 1.00))
        case (.solarFlare, .recording):
            IndicatorPaletteColors(low: Self.color(1.00, 0.18, 0.06), mid: Self.color(1.00, 0.58, 0.10), high: Self.color(1.00, 0.94, 0.32), spark: Self.color(1.00, 0.96, 0.78))
        case (.solarFlare, .transcribing):
            IndicatorPaletteColors(low: Self.color(0.82, 0.08, 0.34), mid: Self.color(1.00, 0.44, 0.12), high: Self.color(1.00, 0.82, 0.24), spark: Self.color(1.00, 0.92, 0.72))
        case (.roseGold, .recording):
            IndicatorPaletteColors(low: Self.color(0.90, 0.28, 0.70), mid: Self.color(1.00, 0.66, 0.46), high: Self.color(0.72, 0.42, 1.00), spark: Self.color(1.00, 0.92, 0.82))
        case (.roseGold, .transcribing):
            IndicatorPaletteColors(low: Self.color(0.72, 0.20, 0.88), mid: Self.color(1.00, 0.42, 0.64), high: Self.color(1.00, 0.76, 0.46), spark: Self.color(1.00, 0.90, 0.94))
        case (.arcticGhost, .recording):
            IndicatorPaletteColors(low: Self.color(0.58, 0.86, 1.00), mid: Self.color(0.88, 1.00, 1.00), high: Self.color(0.42, 0.64, 1.00), spark: NSColor.white)
        case (.arcticGhost, .transcribing):
            IndicatorPaletteColors(low: Self.color(0.66, 0.70, 1.00), mid: Self.color(0.94, 0.86, 1.00), high: Self.color(0.74, 1.00, 1.00), spark: NSColor.white)
        case (.acidMatrix, .recording):
            IndicatorPaletteColors(low: Self.color(0.08, 0.70, 0.24), mid: Self.color(0.58, 1.00, 0.18), high: Self.color(0.10, 1.00, 0.74), spark: Self.color(0.92, 1.00, 0.50))
        case (.acidMatrix, .transcribing):
            IndicatorPaletteColors(low: Self.color(0.18, 0.86, 0.42), mid: Self.color(0.86, 1.00, 0.18), high: Self.color(0.16, 0.96, 1.00), spark: Self.color(0.94, 1.00, 0.62))
        case (.voidGold, .recording):
            IndicatorPaletteColors(low: Self.color(0.10, 0.04, 0.28), mid: Self.color(0.92, 0.58, 0.16), high: Self.color(0.36, 0.18, 0.86), spark: Self.color(1.00, 0.92, 0.62))
        case (.voidGold, .transcribing):
            IndicatorPaletteColors(low: Self.color(0.20, 0.08, 0.42), mid: Self.color(1.00, 0.72, 0.22), high: Self.color(0.66, 0.30, 1.00), spark: Self.color(1.00, 0.96, 0.72))
        case (.deepSpace, .recording):
            IndicatorPaletteColors(low: Self.color(0.02, 0.04, 0.16), mid: Self.color(0.08, 0.18, 0.58), high: Self.color(0.32, 0.12, 0.72), spark: Self.color(0.78, 0.82, 1.00))
        case (.deepSpace, .transcribing):
            IndicatorPaletteColors(low: Self.color(0.04, 0.06, 0.24), mid: Self.color(0.12, 0.28, 0.72), high: Self.color(0.42, 0.22, 0.88), spark: Self.color(0.88, 0.92, 1.00))
        case (.toxicMist, .recording):
            IndicatorPaletteColors(low: Self.color(0.02, 0.22, 0.08), mid: Self.color(0.18, 0.82, 0.24), high: Self.color(0.42, 1.00, 0.38), spark: Self.color(0.88, 1.00, 0.72))
        case (.toxicMist, .transcribing):
            IndicatorPaletteColors(low: Self.color(0.06, 0.28, 0.12), mid: Self.color(0.28, 0.88, 0.34), high: Self.color(0.52, 1.00, 0.48), spark: Self.color(0.92, 1.00, 0.78))
        case (.bloodMoon, .recording):
            IndicatorPaletteColors(low: Self.color(0.28, 0.02, 0.02), mid: Self.color(0.82, 0.08, 0.08), high: Self.color(1.00, 0.28, 0.12), spark: Self.color(1.00, 0.72, 0.62))
        case (.bloodMoon, .transcribing):
            IndicatorPaletteColors(low: Self.color(0.36, 0.04, 0.04), mid: Self.color(0.88, 0.12, 0.12), high: Self.color(1.00, 0.38, 0.18), spark: Self.color(1.00, 0.78, 0.68))
        case (.neonPulse, .recording):
            IndicatorPaletteColors(low: Self.color(0.06, 0.02, 0.18), mid: Self.color(0.08, 0.88, 1.00), high: Self.color(0.48, 0.08, 1.00), spark: Self.color(0.92, 0.98, 1.00))
        case (.neonPulse, .transcribing):
            IndicatorPaletteColors(low: Self.color(0.10, 0.04, 0.24), mid: Self.color(0.14, 0.92, 1.00), high: Self.color(0.58, 0.14, 1.00), spark: Self.color(0.96, 1.00, 1.00))
        case (.cottonCandyKisses, .recording):
            IndicatorPaletteColors(low: Self.color(1.00, 0.32, 0.72), mid: Self.color(1.00, 0.68, 0.90), high: Self.color(0.54, 0.86, 1.00), spark: Self.color(1.00, 0.98, 0.72))
        case (.cottonCandyKisses, .transcribing):
            IndicatorPaletteColors(low: Self.color(0.94, 0.26, 0.78), mid: Self.color(1.00, 0.72, 0.94), high: Self.color(0.72, 0.58, 1.00), spark: Self.color(1.00, 0.96, 0.58))
        }
    }

    private static func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> NSColor {
        NSColor(calibratedRed: red, green: green, blue: blue, alpha: 1)
    }
}

struct IndicatorPaletteColors {
    let low: NSColor
    let mid: NSColor
    let high: NSColor
    let spark: NSColor
}
