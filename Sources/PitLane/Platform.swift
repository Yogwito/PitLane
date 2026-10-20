import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif os(Windows)
import ucrt
import WinSDK
#endif

/// Lo que depende del sistema operativo queda aquí; el resto del intérprete solo usa Foundation.
enum Platform {
    /// Pico de memoria residente del proceso, en bytes, o nil si no se puede medir.
    static func peakResidentBytes() -> Int? {
        #if os(Windows)
        var counters = PROCESS_MEMORY_COUNTERS()
        let size = DWORD(MemoryLayout<PROCESS_MEMORY_COUNTERS>.size)
        counters.cb = size
        guard K32GetProcessMemoryInfo(GetCurrentProcess(), &counters, size) else { return nil }
        return Int(counters.PeakWorkingSetSize)
        #else
        var usage = rusage()
        #if os(Linux)
        guard getrusage(RUSAGE_SELF.rawValue, &usage) == 0 else { return nil }
        return Int(usage.ru_maxrss) * 1024  // Linux informa KiB
        #else
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return nil }
        return Int(usage.ru_maxrss)  // macOS informa bytes
        #endif
        #endif
    }

    /// Tiempo de CPU (usuario + sistema) consumido por este proceso, en segundos.
    /// Esperar el teclado o la salida no consume CPU, así que no cuenta.
    static func cpuSeconds() -> Double {
        #if os(Windows)
        return cpuSeconds(ofProcessHandle: GetCurrentProcess()) ?? 0
        #else
        var usage = rusage()
        #if os(Linux)
        guard getrusage(RUSAGE_SELF.rawValue, &usage) == 0 else { return 0 }
        #else
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return 0 }
        #endif
        func seconds(_ t: timeval) -> Double { Double(t.tv_sec) + Double(t.tv_usec) / 1_000_000 }
        return seconds(usage.ru_utime) + seconds(usage.ru_stime)
        #endif
    }

    #if os(Windows)
    private static func cpuSeconds(ofProcessHandle handle: HANDLE?) -> Double? {
        var creation = FILETIME(), exit = FILETIME(), kernel = FILETIME(), user = FILETIME()
        guard GetProcessTimes(handle, &creation, &exit, &kernel, &user) else { return nil }
        func ticks(_ t: FILETIME) -> UInt64 { UInt64(t.dwHighDateTime) << 32 | UInt64(t.dwLowDateTime) }
        return Double(ticks(kernel) + ticks(user)) / 10_000_000  // unidades de 100 ns
    }
    #endif

    /// Tope de CPU del proceso intérprete. En macOS y Linux lo aplica el sistema operativo
    /// (SIGXCPU); en Windows lo vigila el supervisor en `waitForExit`.
    static func limitCPUTime(seconds: Int) -> Bool {
        #if os(Windows)
        return true
        #else
        #if os(Linux)
        let resource = __rlimit_resource_t(RLIMIT_CPU.rawValue)
        #else
        let resource = RLIMIT_CPU
        #endif
        var limit = rlimit(rlim_cur: rlim_t(seconds), rlim_max: rlim_t(seconds + 1))
        return setrlimit(resource, &limit) == 0
        #endif
    }

    /// Espera a que termine el intérprete; devuelve true si se detuvo por agotar `cpuLimit` segundos de CPU.
    static func waitForExit(_ process: Process, cpuLimit: Int) -> Bool {
        #if os(Windows)
        let handle = OpenProcess(
            DWORD(PROCESS_QUERY_LIMITED_INFORMATION), false, DWORD(process.processIdentifier))
        defer { if let handle = handle { CloseHandle(handle) } }
        while process.isRunning {
            if let used = cpuSeconds(ofProcessHandle: handle), used > Double(cpuLimit) {
                process.terminate()  // TerminateProcess
                process.waitUntilExit()
                return true
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        process.waitUntilExit()
        return false
        #else
        process.waitUntilExit()
        return process.terminationReason == .uncaughtSignal && process.terminationStatus == SIGXCPU
        #endif
    }

    /// Límites que impone el sistema operativo al proceso intérprete (solo Linux).
    static func limitAddressSpace(bytes: Int) -> Bool {
        #if os(Linux)
        let resource = __rlimit_resource_t(RLIMIT_AS.rawValue)
        var limit = rlimit(rlim_cur: rlim_t(bytes), rlim_max: rlim_t(bytes))
        return setrlimit(resource, &limit) == 0
        #else
        return true
        #endif
    }

    /// Salida sin búfer y con saltos de línea LF: en Windows stdout abre en modo texto
    /// y convertiría cada salto de línea en CRLF.
    static func configureStdout() {
        #if os(Windows)
        _ = _setmode(_fileno(stdout), _O_BINARY)
        #endif
        setvbuf(stdout, nil, _IONBF, 0)
    }
}
