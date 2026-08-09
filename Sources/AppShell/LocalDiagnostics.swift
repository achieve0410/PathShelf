import Foundation
import OSLog

enum LocalDiagnostics {
    static let log = Logger(subsystem: "io.github.achieve0410.PathShelf", category: "local")
    static let signposter = OSSignposter(subsystem: "io.github.achieve0410.PathShelf", category: "performance")

    static func userVisibleError(_ message: String) {
        log.error("\(message, privacy: .public)")
    }

    static func state(_ message: String) {
        log.info("\(message, privacy: .public)")
    }
}

struct PanelTimingMetrics {
    var warmLatencyMs: Double
    var coldLatencyMs: Double
    var rssBytes: UInt64

    var machineReadableSummary: String {
        "PERF warm_ms=\(String(format: "%.3f", warmLatencyMs)) cold_ms=\(String(format: "%.3f", coldLatencyMs)) rss_bytes=\(rssBytes)"
    }
}

enum ProcessMetrics {
    static func residentMemoryBytes() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    rebound,
                    &count
                )
            }
        }
        guard result == KERN_SUCCESS else {
            return 0
        }
        return UInt64(info.resident_size)
    }

    static func physicalFootprintBytes() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(
                    mach_task_self_,
                    task_flavor_t(TASK_VM_INFO),
                    rebound,
                    &count
                )
            }
        }
        guard result == KERN_SUCCESS else {
            return 0
        }
        return info.phys_footprint
    }
}
