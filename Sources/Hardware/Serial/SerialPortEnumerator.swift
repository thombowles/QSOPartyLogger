import Foundation
import IOKit
import IOKit.serial

struct SerialPortInfo: Identifiable, Hashable, Sendable {
    let path: String
    var id: String { path }

    var displayName: String {
        path.replacingOccurrences(of: "/dev/cu.", with: "")
    }
}

/// Lists callout (`/dev/cu.*`) serial devices via IOKit.
enum SerialPortEnumerator {
    static func availablePorts() -> [SerialPortInfo] {
        var ports: [SerialPortInfo] = []
        let matching = IOServiceMatching(kIOSerialBSDServiceValue)
        var iterator: io_iterator_t = 0

        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return fallbackScan()
        }
        defer { IOObjectRelease(iterator) }

        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            if let cfPath = IORegistryEntryCreateCFProperty(
                service, kIOCalloutDeviceKey as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue() as? String {
                ports.append(SerialPortInfo(path: cfPath))
            }
        }
        return ports.isEmpty ? fallbackScan() : ports.sorted { $0.path < $1.path }
    }

    private static func fallbackScan() -> [SerialPortInfo] {
        let paths = (try? FileManager.default.contentsOfDirectory(atPath: "/dev")) ?? []
        return paths
            .filter { $0.hasPrefix("cu.") }
            .map { SerialPortInfo(path: "/dev/\($0)") }
            .sorted { $0.path < $1.path }
    }
}
