import Darwin
import Foundation

@main
struct ProcessMetricsProbe {
    static func main() {
        guard CommandLine.arguments.count == 2,
              let pid = Int32(CommandLine.arguments[1]) else {
            fputs("usage: ProcessMetricsProbe <pid>\n", stderr)
            exit(2)
        }

        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rebound in
                proc_pid_rusage(pid, RUSAGE_INFO_V4, rebound)
            }
        }
        guard result == 0 else {
            perror("proc_pid_rusage")
            exit(1)
        }

        print(
            "PROCESS_RUSAGE pid=\(pid) user_ns=\(info.ri_user_time) system_ns=\(info.ri_system_time) disk_read_bytes=\(info.ri_diskio_bytesread) disk_write_bytes=\(info.ri_diskio_byteswritten) phys_footprint_bytes=\(info.ri_phys_footprint)"
        )
    }
}
