import Foundation

extension ControllerClient {
    public func fetchStatus() async throws -> ControllerStatusPayload {
        try await get("/api/status", as: ControllerStatusPayload.self)
    }

    public func fetchDoctorReport() async throws -> DoctorReport {
        try await get("/api/doctor", as: DoctorReport.self)
    }

    public func fetchBenchmarkStatus() async throws -> BenchmarkStatus {
        try await get("/api/benchmark/status", as: BenchmarkStatus.self)
    }

    public func fetchHostMetrics() async throws -> HostMetricsPayload {
        try await get("/api/host/metrics", as: HostMetricsPayload.self)
    }
}
