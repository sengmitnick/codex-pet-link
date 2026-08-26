import Foundation

public struct DeviceIdentity: Codable, Equatable, Sendable {
    public static let maximumAdvertisedNameBytes = 28

    public let advertisedName: String

    public static func loadOrCreate(
        at url: URL,
        computerName: String = Host.current().localizedName ?? ProcessInfo.processInfo.hostName,
        randomSuffix: () -> String = {
            String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(4)).uppercased()
        }
    ) throws -> DeviceIdentity {
        if let data = try? Data(contentsOf: url),
           let saved = try? JSONDecoder().decode(DeviceIdentity.self, from: data),
           saved.advertisedName.hasPrefix("Codex "),
           saved.advertisedName.utf8.count <= maximumAdvertisedNameBytes
        {
            return saved
        }

        let suffix = normalizedSuffix(randomSuffix())
        let reservedBytes = "Codex  \(suffix)".utf8.count
        let hostLimit = max(3, maximumAdvertisedNameBytes - reservedBytes)
        let host = shortenedHostToken(from: computerName, maximumBytes: hostLimit)
        let identity = DeviceIdentity(advertisedName: "Codex \(host) \(suffix)")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode(identity).write(to: url, options: .atomic)
        return identity
    }

    private static func normalizedSuffix(_ value: String) -> String {
        let allowed = value.uppercased().unicodeScalars.filter { scalar in
            (48...57).contains(scalar.value) || (65...90).contains(scalar.value)
        }
        let candidate = String(String.UnicodeScalarView(allowed)).prefix(4)
        return candidate.count == 4 ? String(candidate) : "0000"
    }

    private static func shortenedHostToken(from value: String, maximumBytes: Int) -> String {
        var result = ""
        var needsSeparator = false
        for scalar in value.unicodeScalars {
            let isASCIIAlphaNumeric = (48...57).contains(scalar.value)
                || (65...90).contains(scalar.value)
                || (97...122).contains(scalar.value)
            guard isASCIIAlphaNumeric else {
                if !result.isEmpty { needsSeparator = true }
                continue
            }
            let character = String(scalar)
            let separator = needsSeparator && !result.hasSuffix("-") ? "-" : ""
            if (result + separator + character).utf8.count > maximumBytes { break }
            result += separator + character
            needsSeparator = false
        }
        while result.hasSuffix("-") { result.removeLast() }
        return result.isEmpty ? "Mac" : result
    }
}
