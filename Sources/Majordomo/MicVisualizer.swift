import AVFoundation
import Accelerate

final class MicVisualizer: @unchecked Sendable {
    private let fftSize = 2048
    private let bandCount = 64
    private let log2n: vDSP_Length
    private let fftSetup: FFTSetup
    private let window: [Float]
    fileprivate(set) var levels: [Float]

    init() {
        log2n = vDSP_Length(log2(Float(fftSize)))
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        var win = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&win, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        window = win
        levels = [Float](repeating: 0, count: bandCount)
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }

    func process(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData,
              buffer.frameLength > 0 else { return }

        let frameCount = Int(buffer.frameLength)
        var padded = [Float](repeating: 0, count: fftSize)
        let copyCount = min(frameCount, fftSize)

        for i in 0..<copyCount {
            padded[i] = channelData[0][i] * window[i]
        }

        var real = [Float](repeating: 0, count: fftSize / 2)
        var imag = [Float](repeating: 0, count: fftSize / 2)

        padded.withUnsafeMutableBytes { rawPtr in
            let ptr = rawPtr.bindMemory(to: Float.self).baseAddress!
            real.withUnsafeMutableBufferPointer { realPtr in
                imag.withUnsafeMutableBufferPointer { imagPtr in
                    guard let realBase = realPtr.baseAddress,
                          let imagBase = imagPtr.baseAddress else { return }
                    var dspSplit = DSPSplitComplex(realp: realBase, imagp: imagBase)
                    ptr.withMemoryRebound(to: DSPComplex.self, capacity: fftSize / 2) { complexPtr in
                        vDSP_ctoz(complexPtr, 2, &dspSplit, 1, vDSP_Length(fftSize / 2))
                    }
                    vDSP_fft_zrip(fftSetup, &dspSplit, 1, log2n, FFTDirection(kFFTDirection_Forward))

                    var mags = [Float](repeating: 0, count: fftSize / 2)
                    vDSP_zvmags(&dspSplit, 1, &mags, 1, vDSP_Length(fftSize / 2))

                    let fs = Float(buffer.format.sampleRate)
                    let fMin: Float = 60
                    let fMax = min(fs / 2, 8000)
                    let binHz = fs / Float(fftSize)

                    for b in 0..<bandCount {
                        let lo = fMin * pow(fMax / fMin, Float(b) / Float(bandCount))
                        let hi = fMin * pow(fMax / fMin, Float(b + 1) / Float(bandCount))
                        let k0 = max(1, Int(lo / binHz))
                        let k1 = max(k0 + 1, Int(hi / binHz))

                        var peak: Float = 0
                        for k in k0..<min(k1, mags.count) { peak = max(peak, mags[k]) }

                        let db = 10 * log10(max(peak, 1e-10))
                        let raw = max(0, min(1, (db + 60) / 60))
                        let shaped = pow(raw, 2.5)
                        var t = max(0, min(1, shaped))
                        t *= 0.4 + 0.6 * Float(b) / Float(bandCount)

                        let attack: Float = 0.6
                        let release: Float = 0.12
                        var current = levels[b]
                        current += (t > current ? attack : release) * (t - current)
                        levels[b] = current
                    }
                }
            }
        }
    }
}
