import Foundation

/// Frequency↔pixel mapping for the band map: a zoom window over one band,
/// centered on the VFO and clamped to the band edges. High frequency at the
/// top, like every band map hams have ever used.
struct BandMapScale: Equatable {
    let lowKHz: Double
    let highKHz: Double

    init(band: Band, centerKHz: Double?, spanKHz: Double) {
        let range = band.rangeKHz
        let bandLow = Double(range.lowerBound)
        let bandHigh = Double(range.upperBound)
        let span = min(spanKHz, bandHigh - bandLow)
        let center = centerKHz ?? (bandLow + bandHigh) / 2
        let low = max(bandLow, min(center - span / 2, bandHigh - span))
        self.lowKHz = low
        self.highKHz = low + span
    }

    var spanKHz: Double { highKHz - lowKHz }

    func y(forKHz kHz: Double, height: Double) -> Double {
        (highKHz - kHz) / spanKHz * height
    }

    func kHz(atY y: Double, height: Double) -> Double {
        highKHz - y / height * spanKHz
    }

    /// Gridline frequencies: a "nice" step (~1/8 span) aligned to multiples.
    func tickKHz() -> [Double] {
        let step = Self.niceStep(atLeast: spanKHz / 8)
        var ticks: [Double] = []
        var tick = (lowKHz / step).rounded(.up) * step
        while tick <= highKHz + 0.001 {
            ticks.append(tick)
            tick += step
        }
        return ticks
    }

    private static func niceStep(atLeast minStep: Double) -> Double {
        for step in [1.0, 2, 5, 10, 20, 25, 50, 100] where step >= minStep {
            return step
        }
        return 100
    }
}
