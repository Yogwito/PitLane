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

// Todo lo que cambia segun el sistema operativo (mac, linux, windows) lo pusimos aqui
enum Platform {
    // maximo de memoria que ha usado el proceso (en bytes). nil si no se puede saber
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
        return Int(usage.ru_maxrss) * 1024  // linux lo da en KB
        #else
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return nil }
        return Int(usage.ru_maxrss)  // mac lo da en bytes
        #endif
        #endif
    }

    // segundos de CPU que lleva el proceso. Si esta esperando el teclado no cuenta
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
        return Double(ticks(kernel) + ticks(user)) / 10_000_000  // windows cuenta en pedazos de 100 ns
    }
    #endif

    // limite de CPU. En mac y linux lo pone el sistema (SIGXCPU),
    // en windows no se puede asi que lo revisa waitForExit
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

    // espera a que el proceso hijo termine. true = lo matamos por pasarse de tiempo
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

    // limites que pone el sistema operativo (esto solo aplica en linux)
    static func limitAddressSpace(bytes: Int) -> Bool {
        #if os(Linux)
        let resource = __rlimit_resource_t(RLIMIT_AS.rawValue)
        var limit = rlimit(rlim_cur: rlim_t(bytes), rlim_max: rlim_t(bytes))
        return setrlimit(resource, &limit) == 0
        #else
        return true
        #endif
    }

    // stdout sin buffer. En windows ademas toca evitar que cambie \n por \r\n
    static func configureStdout() {
        #if os(Windows)
        _ = _setmode(_fileno(stdout), _O_BINARY)
        #endif
        setvbuf(stdout, nil, _IONBF, 0)
    }
}
