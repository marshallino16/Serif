import Foundation
import Darwin.Mach
import os

final class CPUMonitor: Sendable {
    static let shared = CPUMonitor()

    // All mutable state protected by os_unfair_lock
    private let lock = OSAllocatedUnfairLock(initialState: State())

    private struct State {
        var previousProcessTime: Double = 0
        var previousWallTime: UInt64 = 0
        var cachedUsage: Double = 0
        var cacheTimestamp: UInt64 = 0
    }

    /// Minimum interval between real samples (500ms)
    private let cacheInterval: UInt64 = 500_000_000
    /// Process CPU threshold (Activity Monitor scale: 100 = one full core)
    private let cpuThreshold: Double = 50

    private init() {
        // Prime the first sample
        let now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        let time = Self.processTime() ?? 0
        lock.withLock { state in
            state.previousProcessTime = time
            state.previousWallTime = now
        }
    }

    // MARK: - Public API

    /// Process CPU usage on Activity Monitor scale (100 = one full core, 200 = two cores, etc).
    /// Cached for 500ms to avoid micro-deltas from rapid successive calls.
    func processCPUUsage() -> Double {
        let now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        return lock.withLock { state in
            if now - state.cacheTimestamp < cacheInterval {
                return state.cachedUsage
            }
            guard let currentTime = Self.processTime() else { return state.cachedUsage }

            let wallDelta = Double(now - state.previousWallTime) / 1_000_000_000
            guard wallDelta > 0.01 else { return state.cachedUsage } // need at least 10ms of wall time

            let cpuDelta = currentTime - state.previousProcessTime
            let usage = (cpuDelta / wallDelta) * 100

            state.previousProcessTime = currentTime
            state.previousWallTime = now
            state.cachedUsage = usage
            state.cacheTimestamp = now
            return usage
        }
    }

    /// Recommended concurrency (1...max) based on process CPU.
    func recommendedConcurrency(max: Int) -> Int {
        let usage = processCPUUsage()
        if usage > cpuThreshold * 1.5 { return 1 }                    // 75%+ → serial
        if usage > cpuThreshold { return Swift.max(1, max - 1) }       // 50-75% → reduce
        return max
    }

    /// Delay in nanoseconds, multiplied based on process CPU.
    func recommendedDelay(base: UInt64) -> UInt64 {
        let usage = processCPUUsage()
        if usage > cpuThreshold * 2 { return base * 4 }     // 100%+ (full core)
        if usage > cpuThreshold * 1.5 { return base * 3 }   // 75%+
        if usage > cpuThreshold { return base * 2 }          // 50%+
        return base
    }

    /// Hard gate: suspends until process CPU drops below threshold.
    func throttleIfNeeded() async {
        while processCPUUsage() > cpuThreshold {
            try? await Task.sleep(nanoseconds: cacheInterval)
        }
    }

    // MARK: - Private

    /// Total CPU time (user + system) consumed by this process, in seconds.
    private static func processTime() -> Double? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let userSec = Double(info.user_time.seconds) + Double(info.user_time.microseconds) / 1_000_000
        let sysSec = Double(info.system_time.seconds) + Double(info.system_time.microseconds) / 1_000_000
        return userSec + sysSec
    }
}
