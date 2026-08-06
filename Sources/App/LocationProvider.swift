import CoreLocation
import Foundation

/// A position, in the only two numbers this app needs from Core Location.
struct LocationFix: Equatable, Sendable {
    let latitude: Double
    let longitude: Double
}

/// Why a location could not be had — and, in the operator's words, what to
/// do about it. One sentence per cause: "couldn't get a location" covered a
/// denied permission and a Mac that simply cannot see itself, which are
/// different problems with different fixes.
enum LocationFailure: Error, Equatable, Sendable {
    /// Denied or restricted — only the operator can undo it.
    case denied
    /// Core Location has no idea where this Mac is (no Wi-Fi networks it
    /// recognises, no other positioning source).
    case unavailable
    /// Nothing came back in time.
    case timedOut
    /// Anything else, in the framework's own words.
    case failed(String)

    /// Every one of these ends by naming the grid square field, because
    /// typing it is always available and always works.
    var message: String {
        switch self {
        case .denied:
            "Location access is off for QSO Party Logger — turn it on in System "
                + "Settings › Privacy & Security › Location Services, or type the "
                + "grid square."
        case .unavailable:
            "This Mac couldn't work out where it is — type the grid square instead."
        case .timedOut:
            "Location didn't answer in time — try again, or type the grid square."
        case .failed(let reason):
            "Couldn't get a location (\(reason)) — type the grid square instead."
        }
    }

    /// Core Location's own error codes (CLError.h: kCLErrorLocationUnknown
    /// = 0, kCLErrorDenied = 1, kCLErrorNetwork = 2). A network error and an
    /// unknown location are the same thing to the operator: the Mac cannot
    /// place itself right now.
    static func from(_ error: Error) -> LocationFailure {
        let nsError = error as NSError
        guard nsError.domain == CLError.errorDomain else {
            return .failed(nsError.localizedDescription)
        }
        switch CLError.Code(rawValue: nsError.code) {
        case .denied: return .denied
        case .locationUnknown, .network: return .unavailable
        default: return .failed(nsError.localizedDescription)
        }
    }
}

/// One-shot position for Contest Setup: fill the grid square, anchor the
/// park picker's nearest-first sort.
///
/// A seam in the keying-path sense — tests supply positions and failures,
/// and only the live implementation touches Core Location.
protocol LocationProviding {
    /// Already granted, so a silent fill will not raise the permission
    /// dialog.
    @MainActor var isAuthorized: Bool { get }
    @MainActor func currentLocation() async -> Result<LocationFix, LocationFailure>
}

/// Turning a position into the grid square the field shows. Separated from
/// the view so the outcome of every path is assertable.
enum GridLocate {

    enum Outcome: Equatable {
        case filled(grid: String, fix: LocationFix)
        case failed(message: String)
    }

    /// Main-actor bound like the provider it drives: the protocol's members
    /// are `@MainActor`, so a nonisolated caller would have to send the
    /// provider across an actor boundary to reach them.
    @MainActor
    static func run(_ provider: any LocationProviding) async -> Outcome {
        switch await provider.currentLocation() {
        case .failure(let failure):
            return .failed(message: failure.message)
        case .success(let fix):
            guard let grid = Maidenhead.locator(latitude: fix.latitude,
                                                longitude: fix.longitude) else {
                // Off the globe: Core Location should never produce this, so
                // it says so plainly rather than blaming the operator.
                return .failed(message: LocationFailure
                    .failed("\(fix.latitude), \(fix.longitude) is not on the map")
                    .message)
            }
            return .filled(grid: grid, fix: fix)
        }
    }
}

/// The live Core Location wrapper.
///
/// **Authorization is awaited, never assumed.** `requestWhenInUseAuthorization`
/// only ever prompts; the answer arrives later on
/// `locationManagerDidChangeAuthorization` (CLLocationManager.h: "Any
/// authorization change as a result of the prompt will be reflected via the
/// usual delegate callback"). The first version of this file called
/// `requestLocation()` in the same breath as the prompt, so the very first
/// press raced the grant and always failed.
///
/// Each ask carries a generation number so a previous ask's timeout cannot
/// answer the current one — the second bug of that pair, and the reason
/// pressing Locate again looked just as broken.
@MainActor
final class MacLocationProvider: NSObject, LocationProviding, CLLocationManagerDelegate {

    private let manager = CLLocationManager()
    private var fixContinuation: CheckedContinuation<Result<LocationFix, LocationFailure>, Never>?
    private var authContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?
    /// Bumped per ask; a timeout only fires for the ask that armed it.
    private var generation = 0

    /// A fix over Wi-Fi positioning normally lands in a second or two.
    private static let fixTimeout = Duration.seconds(15)
    private static let authTimeout = Duration.seconds(60)

    override init() {
        super.init()
        manager.delegate = self
        // A park is not a street address: hundreds of metres is plenty for a
        // 6-character grid square and a distance sort, and it fixes faster.
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var isAuthorized: Bool {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: true
        default: false
        }
    }

    func currentLocation() async -> Result<LocationFix, LocationFailure> {
        generation += 1
        let ask = generation
        // Any earlier ask still waiting is answered now, so it cannot be
        // left hanging on a continuation nobody will resume.
        resumeFix(with: .failure(.timedOut))

        var status = manager.authorizationStatus
        if status == .notDetermined {
            status = await requestAuthorization(ask: ask)
        }
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            break
        case .notDetermined:
            // The prompt never resolved — treat as "not granted" rather than
            // firing a request that is documented to fail.
            return .failure(.timedOut)
        default:
            return .failure(.denied)
        }

        return await withCheckedContinuation { continuation in
            fixContinuation = continuation
            manager.requestLocation()
            armTimeout(ask: ask, after: Self.fixTimeout, failure: .timedOut)
        }
    }

    /// Prompt, then wait for the delegate to say what the operator chose.
    private func requestAuthorization(ask: Int) async -> CLAuthorizationStatus {
        await withCheckedContinuation { continuation in
            authContinuation = continuation
            manager.requestWhenInUseAuthorization()
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: Self.authTimeout)
                guard let self, self.generation == ask else { return }
                self.resumeAuth(with: self.manager.authorizationStatus)
            }
        }
    }

    private func armTimeout(ask: Int, after duration: Duration,
                            failure: LocationFailure) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: duration)
            guard let self, self.generation == ask else { return }
            self.resumeFix(with: .failure(failure))
        }
    }

    /// Resume at most once per ask — the timeout and the delegate race, and
    /// resuming a continuation twice traps.
    private func resumeFix(with result: Result<LocationFix, LocationFailure>) {
        guard let pending = fixContinuation else { return }
        fixContinuation = nil
        pending.resume(returning: result)
    }

    private func resumeAuth(with status: CLAuthorizationStatus) {
        guard let pending = authContinuation else { return }
        authContinuation = nil
        pending.resume(returning: status)
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in
            // Fires once when the delegate is first set, too — harmless,
            // because nothing is waiting then.
            guard status != .notDetermined else { return }
            self?.resumeAuth(with: status)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        let coordinate = locations.last?.coordinate
        Task { @MainActor [weak self] in
            guard let coordinate else {
                self?.resumeFix(with: .failure(.unavailable))
                return
            }
            self?.resumeFix(with: .success(LocationFix(latitude: coordinate.latitude,
                                                       longitude: coordinate.longitude)))
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didFailWithError error: Error) {
        let failure = LocationFailure.from(error)
        Task { @MainActor [weak self] in
            self?.resumeFix(with: .failure(failure))
        }
    }
}
