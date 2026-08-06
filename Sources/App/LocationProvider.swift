import CoreLocation

/// One-shot position for Contest Setup: fill the grid square, anchor the
/// park picker's nearest-first sort.
///
/// A seam in the keying-path sense — previews and tests supply positions,
/// and only the live implementation touches Core Location. Nothing here is
/// unit-tested: it is glue over a system framework, verified in the running
/// app.
protocol LocationProviding {
    /// Already granted, so a silent fill will not raise the permission
    /// dialog.
    @MainActor var isAuthorized: Bool { get }
    /// One position, or `nil` when denied, unavailable, or timed out.
    @MainActor func currentLocation() async -> (latitude: Double, longitude: Double)?
}

/// The live Core Location wrapper: one `requestLocation()` per ask, the
/// permission prompt only ever from an explicit button press (the silent
/// path checks `isAuthorized` first), and a timeout so a fix that never
/// arrives returns `nil` instead of pinning the sheet.
@MainActor
final class MacLocationProvider: NSObject, LocationProviding, CLLocationManagerDelegate {

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<(latitude: Double, longitude: Double)?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        // A park is not a street address: hundreds of metres is plenty for a
        // 6-character grid square and a distance sort, and it fixes faster.
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var isAuthorized: Bool {
        manager.authorizationStatus == .authorizedAlways
    }

    func currentLocation() async -> (latitude: Double, longitude: Double)? {
        // A second ask while one is in flight would strand the stored
        // continuation — answer the older one with nothing first.
        finish(with: nil)
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        return await withCheckedContinuation { cont in
            continuation = cont
            manager.requestLocation()
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(12))
                self?.finish(with: nil)
            }
        }
    }

    /// Resume at most once per ask — the timeout and the delegate race, and
    /// resuming a continuation twice traps.
    private func finish(with fix: (latitude: Double, longitude: Double)?) {
        guard let pending = continuation else { return }
        continuation = nil
        pending.resume(returning: fix)
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        let fix = locations.last?.coordinate
        Task { @MainActor [weak self] in
            self?.finish(with: fix.map { ($0.latitude, $0.longitude) })
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.finish(with: nil)
        }
    }
}
