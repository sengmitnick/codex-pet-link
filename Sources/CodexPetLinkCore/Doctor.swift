import Foundation

public enum DoctorOverall: String, Codable, Equatable, Sendable {
    case healthy
    case needsAttention
}

public struct DoctorReport: Codable, Equatable, Sendable {
    public var executableInstalled: Bool
    public var sessionsAvailable: Bool
    public var serviceLoaded: Bool
    public var dataDirectory: String
    public var advertisedName: String

    public var overall: DoctorOverall {
        executableInstalled && sessionsAvailable && serviceLoaded ? .healthy : .needsAttention
    }
}

public struct Doctor: Sendable {
    private let paths: ServicePaths
    private let serviceLoaded: @Sendable () -> Bool

    public init(paths: ServicePaths, serviceLoaded: @escaping @Sendable () -> Bool) {
        self.paths = paths
        self.serviceLoaded = serviceLoaded
    }

    public func inspect() -> DoctorReport {
        let manager = FileManager.default
        let identity = try? DeviceIdentity.loadOrCreate(at: paths.deviceIdentity)
        return DoctorReport(
            executableInstalled: manager.isExecutableFile(atPath: paths.executable.path)
                || manager.fileExists(atPath: paths.executable.path),
            sessionsAvailable: manager.fileExists(atPath: paths.sessions.path),
            serviceLoaded: serviceLoaded(),
            dataDirectory: paths.dataDirectory.path,
            advertisedName: identity?.advertisedName ?? "Codex Mac 0000"
        )
    }
}

public struct LinkConfiguration: Codable, Equatable, Sendable {
    public var titlesEnabled: Bool

    public init(titlesEnabled: Bool = true) {
        self.titlesEnabled = titlesEnabled
    }

    public static func load(from url: URL) -> LinkConfiguration {
        guard let data = try? Data(contentsOf: url),
              let value = try? JSONDecoder().decode(LinkConfiguration.self, from: data)
        else {
            return LinkConfiguration()
        }
        return value
    }

    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }
}
