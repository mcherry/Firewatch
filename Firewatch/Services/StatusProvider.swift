import Foundation

protocol StatusProvider: Sendable {
    var serviceName: String { get }
    var sortOrder: Int { get }
    func fetchStatus() async throws -> ServiceInfo
}
