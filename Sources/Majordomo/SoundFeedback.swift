import AppKit
import MajordomoCore

enum DictationSoundProfile: String, CaseIterable {
    case majordomoChime
    case starshipConsole
    case rotaryExchange
    case classicDesktop
    case aquaGlass
    case terminalTick
    case cassetteRelay
    case arcadeBlip
    case ufoScanner
    case crystalBell

    static let userDefaultsKey = DefaultsKey.dictationSoundProfile
    static let defaultProfile: DictationSoundProfile = .majordomoChime

    var displayName: String {
        switch self {
        case .majordomoChime: "Majordomo Chime"
        case .starshipConsole: "Starship Console"
        case .rotaryExchange: "Rotary Exchange"
        case .classicDesktop: "Classic Desktop"
        case .aquaGlass: "Aqua Glass"
        case .terminalTick: "Terminal Tick"
        case .cassetteRelay: "Cassette Relay"
        case .arcadeBlip: "Arcade Blip"
        case .ufoScanner: "UFO Scanner"
        case .crystalBell: "Crystal Bell"
        }
    }

    static func load(from defaults: UserDefaults = .standard) -> DictationSoundProfile {
        guard let rawValue = defaults.string(forKey: userDefaultsKey),
              let profile = DictationSoundProfile(rawValue: rawValue) else {
            return defaultProfile
        }
        return profile
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.userDefaultsKey)
    }
}

@MainActor
enum SoundFeedback {
    private enum Gesture {
        case start
        case stop
    }

    private enum TextureKind {
        case cleanChime
        case starship
        case rotary
        case desktop
        case aqua
        case terminal
        case cassette
        case arcade
        case ufo
        case crystal
    }

    private struct SoundSpec {
        let texture: TextureKind
        let pitchScale: Double
        let duration: Double
        let volume: Double
        let textureAmount: Double
        let transientAmount: Double
        let roomAmount: Double
    }

    private struct SoundSet {
        let start: NSSound?
        let stop: NSSound?
    }

    private static let sampleRate = 44_100
    private static let baselineStartContour = [880.00, 1318.51, 1760.00]
    private static let baselineStopContour = [1318.51, 880.00, 659.25]

    private static let sounds: [DictationSoundProfile: SoundSet] = Dictionary(
        uniqueKeysWithValues: DictationSoundProfile.allCases.map { profile in
            let spec = soundSpec(for: profile)
            return (
                profile,
                SoundSet(
                    start: NSSound(data: makeWAVData(gesture: .start, spec: spec)),
                    stop: NSSound(data: makeWAVData(gesture: .stop, spec: spec))
                )
            )
        }
    )

    static func playStart(for profile: DictationSoundProfile) {
        play(sounds[profile]?.start ?? sounds[.majordomoChime]?.start)
    }

    static func playStop(for profile: DictationSoundProfile) {
        play(sounds[profile]?.stop ?? sounds[.majordomoChime]?.stop)
    }

    static func exportPreviewSounds(to directoryURL: URL) throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        for profile in DictationSoundProfile.allCases {
            let spec = soundSpec(for: profile)
            let safeName = profile.displayName.replacingOccurrences(of: " ", with: "-").lowercased()
            try makeWAVData(gesture: .start, spec: spec).write(to: directoryURL.appendingPathComponent("\(safeName)-start.wav"))
            try makeWAVData(gesture: .stop, spec: spec).write(to: directoryURL.appendingPathComponent("\(safeName)-stop.wav"))
        }
    }

    private static func soundSpec(for profile: DictationSoundProfile) -> SoundSpec {
        switch profile {
        case .majordomoChime:
            SoundSpec(texture: .cleanChime, pitchScale: 1.00, duration: 0.18, volume: 0.24, textureAmount: 0.020, transientAmount: 0.018, roomAmount: 0.030)
        case .starshipConsole:
            SoundSpec(texture: .starship, pitchScale: 0.93, duration: 0.22, volume: 0.22, textureAmount: 0.105, transientAmount: 0.012, roomAmount: 0.040)
        case .rotaryExchange:
            SoundSpec(texture: .rotary, pitchScale: 0.72, duration: 0.20, volume: 0.23, textureAmount: 0.115, transientAmount: 0.016, roomAmount: 0.018)
        case .classicDesktop:
            SoundSpec(texture: .desktop, pitchScale: 1.04, duration: 0.19, volume: 0.22, textureAmount: 0.075, transientAmount: 0.014, roomAmount: 0.030)
        case .aquaGlass:
            SoundSpec(texture: .aqua, pitchScale: 1.10, duration: 0.21, volume: 0.21, textureAmount: 0.092, transientAmount: 0.012, roomAmount: 0.042)
        case .terminalTick:
            SoundSpec(texture: .terminal, pitchScale: 0.86, duration: 0.13, volume: 0.20, textureAmount: 0.090, transientAmount: 0.020, roomAmount: 0.010)
        case .cassetteRelay:
            SoundSpec(texture: .cassette, pitchScale: 0.80, duration: 0.24, volume: 0.22, textureAmount: 0.120, transientAmount: 0.018, roomAmount: 0.022)
        case .arcadeBlip:
            SoundSpec(texture: .arcade, pitchScale: 1.00, duration: 0.16, volume: 0.20, textureAmount: 0.090, transientAmount: 0.018, roomAmount: 0.014)
        case .ufoScanner:
            SoundSpec(texture: .ufo, pitchScale: 0.88, duration: 0.23, volume: 0.22, textureAmount: 0.120, transientAmount: 0.010, roomAmount: 0.034)
        case .crystalBell:
            SoundSpec(texture: .crystal, pitchScale: 1.12, duration: 0.22, volume: 0.20, textureAmount: 0.105, transientAmount: 0.010, roomAmount: 0.038)
        }
    }

    private static func play(_ sound: NSSound?) {
        guard let sound else {
            NSSound.beep()
            return
        }
        sound.stop()
        sound.currentTime = 0
        sound.play()
    }

    private static func makeWAVData(gesture: Gesture, spec: SoundSpec) -> Data {
        let duration = gesture == .start ? spec.duration : max(0.12, spec.duration * 0.86)
        let sampleCount = max(1, Int(duration * Double(sampleRate)))
        let contour = (gesture == .start ? baselineStartContour : baselineStopContour).map { $0 * spec.pitchScale }
        let attack = gesture == .start ? 0.006 : 0.004
        let release = gesture == .start ? min(0.090, duration * 0.45) : min(0.095, duration * 0.52)

        var samples = [Double](repeating: 0, count: sampleCount)
        for index in 0..<sampleCount {
            let time = Double(index) / Double(sampleRate)
            let progress = Double(index) / Double(max(1, sampleCount - 1))
            let env = envelope(time: time, duration: duration, attack: attack, release: release)
            let tonalGlue = tonalCore(time: time, progress: progress, frequencies: contour) * env * spec.volume * tonalGlueAmount(for: spec.texture)
            let transient = softTransient(time: time, frequency: contour[0] * transientRatio(for: spec.texture)) * spec.transientAmount
            let texture = textureLayer(spec.texture, gesture: gesture, time: time, progress: progress, baseFrequency: contour[1]) * env * spec.textureAmount
            samples[index] = tonalGlue + transient + texture
        }

        addRoom(to: &samples, amount: spec.roomAmount, texture: spec.texture)
        smoothAndLimit(&samples)
        return makeMonoWAVData(from: samples)
    }

    private static func tonalGlueAmount(for texture: TextureKind) -> Double {
        switch texture {
        case .cleanChime: 1.00
        case .desktop, .aqua, .crystal: 0.30
        case .starship, .ufo: 0.20
        case .rotary, .terminal, .cassette, .arcade: 0.12
        }
    }

    private static func transientRatio(for texture: TextureKind) -> Double {
        switch texture {
        case .terminal, .cassette, .rotary: 1.1
        case .crystal, .aqua: 2.5
        case .arcade: 1.8
        default: 1.4
        }
    }

    private static func tonalCore(time: Double, progress: Double, frequencies: [Double]) -> Double {
        var sample = 0.0
        for (toneIndex, frequency) in frequencies.enumerated() {
            let toneProgress = frequencies.count == 1 ? 1.0 : Double(toneIndex) / Double(frequencies.count - 1)
            let blend = max(0, 1.0 - abs(progress - toneProgress) * 1.70)
            sample += blend * (sin(2 * .pi * frequency * time) + 0.10 * sin(2 * .pi * frequency * 2.0 * time))
        }
        return sample / Double(max(1, frequencies.count))
    }

    private static func softTransient(time: Double, frequency: Double) -> Double {
        let fadeIn = min(1.0, time / 0.0025)
        let decay = exp(-time * 130.0)
        return fadeIn * decay * (sin(2 * .pi * frequency * time) + 0.28 * sin(2 * .pi * frequency * 1.5 * time))
    }

    private static func textureLayer(_ texture: TextureKind, gesture: Gesture, time: Double, progress: Double, baseFrequency: Double) -> Double {
        let direction = gesture == .start ? 1.0 : -1.0
        let travel = gesture == .start ? progress : 1.0 - progress
        let noise = shapedNoise(time: time)
        switch texture {
        case .cleanChime:
            return 0.20 * sin(2 * .pi * baseFrequency * 2.0 * time) + 0.08 * noise
        case .starship:
            let scanner = sin(2 * .pi * (baseFrequency * (0.38 + travel * 0.30)) * time + direction * travel * .pi)
            let servo = packetGate(time: time + 0.004, rate: 18.0) * sin(2 * .pi * baseFrequency * 1.7 * time)
            return 0.44 * scanner + 0.28 * servo + 0.18 * noise
        case .rotary:
            let relayA = impulse(time: time, at: gesture == .start ? 0.018 : 0.030, width: 0.004)
            let relayB = impulse(time: time, at: gesture == .start ? 0.072 : 0.058, width: 0.006)
            let lineTone = sin(2 * .pi * 440.0 * time) * (0.5 + 0.5 * sin(2 * .pi * 12.0 * time))
            return 0.55 * relayA * noise + 0.40 * relayB * sin(2 * .pi * 240.0 * time) + 0.22 * lineTone
        case .desktop:
            let softBell = sin(2 * .pi * baseFrequency * 1.25 * time) + 0.32 * sin(2 * .pi * baseFrequency * 1.875 * time)
            let mouse = impulse(time: time, at: 0.012, width: 0.004) * noise
            return 0.42 * softBell + 0.22 * mouse
        case .aqua:
            let droplet = impulse(time: time, at: 0.020, width: 0.008) - 0.55 * impulse(time: time, at: 0.064, width: 0.014)
            let glass = sin(2 * .pi * baseFrequency * 2.4 * time)
            return 0.46 * droplet * glass + 0.28 * sin(2 * .pi * baseFrequency * 0.72 * time)
        case .terminal:
            let tick = packetGate(time: time, rate: gesture == .start ? 42.0 : 31.0)
            return 0.52 * tick * sin(2 * .pi * 880.0 * time) + 0.28 * impulse(time: time, at: 0.010, width: 0.003) * noise
        case .cassette:
            let clackA = impulse(time: time, at: 0.014, width: 0.004) * noise
            let clackB = impulse(time: time, at: 0.082, width: 0.007) * sin(2 * .pi * 190.0 * time)
            let motor = sin(2 * .pi * 58.0 * time + sin(2 * .pi * 7.0 * time) * 0.3)
            return 0.42 * clackA + 0.36 * clackB + 0.20 * motor
        case .arcade:
            let stepped = gesture == .start ? floor(travel * 4.0) / 4.0 : floor((1.0 - travel) * 4.0) / 4.0
            let squareish = sin(2 * .pi * baseFrequency * (0.70 + stepped) * time) > 0 ? 1.0 : -1.0
            return 0.34 * squareish + 0.20 * sin(2 * .pi * baseFrequency * 2.0 * time)
        case .ufo:
            let beam = sin(2 * .pi * baseFrequency * 0.34 * time + sin(2 * .pi * 7.5 * time) * 1.2)
            let sweep = sin(2 * .pi * baseFrequency * (1.2 + direction * travel * 0.5) * time)
            return 0.46 * beam + 0.24 * sweep + 0.16 * noise
        case .crystal:
            let shardA = impulse(time: time, at: 0.015, width: 0.004) * sin(2 * .pi * baseFrequency * 2.8 * time)
            let shardB = impulse(time: time, at: 0.048, width: 0.006) * sin(2 * .pi * baseFrequency * 3.7 * time)
            let shimmer = sin(2 * .pi * baseFrequency * 2.2 * time)
            return 0.54 * shardA + 0.36 * shardB + 0.22 * shimmer
        }
    }

    private static func addRoom(to samples: inout [Double], amount: Double, texture: TextureKind) {
        guard amount > 0 else { return }
        let original = samples
        let taps: [(Double, Double)]
        switch texture {
        case .cleanChime, .desktop: taps = [(0.018, 0.35), (0.044, 0.18)]
        case .starship, .ufo: taps = [(0.026, 0.34), (0.071, 0.20), (0.126, 0.10)]
        case .aqua, .crystal: taps = [(0.012, 0.36), (0.039, 0.24), (0.088, 0.12)]
        case .rotary, .terminal, .cassette, .arcade: taps = [(0.011, 0.20), (0.029, 0.10)]
        }
        for index in samples.indices {
            for tap in taps {
                let delay = Int(tap.0 * Double(sampleRate))
                if index >= delay {
                    samples[index] += original[index - delay] * amount * tap.1
                }
            }
        }
    }

    private static func impulse(time: Double, at center: Double, width: Double) -> Double {
        let distance = (time - center) / max(0.0001, width)
        return exp(-distance * distance)
    }

    private static func packetGate(time: Double, rate: Double) -> Double {
        pow(max(0, sin(2 * .pi * rate * time)), 8.0)
    }

    private static func shapedNoise(time: Double) -> Double {
        let x = sin(time * 12_989.0) * 43_758.5453
        let frac = x - floor(x)
        return (frac * 2.0 - 1.0) * sin(2 * .pi * 37.0 * time)
    }

    private static func smoothAndLimit(_ samples: inout [Double]) {
        var previous = 0.0
        for index in samples.indices {
            let smoothed = previous * 0.18 + samples[index] * 0.82
            previous = smoothed
            samples[index] = tanh(smoothed * 1.48) / tanh(1.48)
        }
    }

    private static func makeMonoWAVData(from samples: [Double]) -> Data {
        let channels = 1
        let bitsPerSample = 16
        let bytesPerSample = bitsPerSample / 8
        let byteRate = sampleRate * channels * bytesPerSample
        let blockAlign = channels * bytesPerSample
        let dataSize = samples.count * blockAlign

        var data = Data()
        data.appendASCII("RIFF")
        data.appendUInt32LE(UInt32(36 + dataSize))
        data.appendASCII("WAVE")
        data.appendASCII("fmt ")
        data.appendUInt32LE(16)
        data.appendUInt16LE(1)
        data.appendUInt16LE(UInt16(channels))
        data.appendUInt32LE(UInt32(sampleRate))
        data.appendUInt32LE(UInt32(byteRate))
        data.appendUInt16LE(UInt16(blockAlign))
        data.appendUInt16LE(UInt16(bitsPerSample))
        data.appendASCII("data")
        data.appendUInt32LE(UInt32(dataSize))

        for sample in samples {
            let value = Int16(max(-1, min(1, sample)) * Double(Int16.max))
            data.appendInt16LE(value)
        }

        return data
    }

    private static func envelope(time: Double, duration: Double, attack: Double, release: Double) -> Double {
        if time < attack {
            return time / attack
        }
        let remaining = duration - time
        if remaining < release {
            return max(0, remaining / release)
        }
        return 1
    }
}

private extension Data {
    mutating func appendASCII(_ string: String) {
        append(Data(string.utf8))
    }

    mutating func appendUInt16LE(_ value: UInt16) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 24) & 0xff))
    }

    mutating func appendInt16LE(_ value: Int16) {
        appendUInt16LE(UInt16(bitPattern: value))
    }
}
