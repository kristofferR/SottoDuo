import Foundation

/// Bundle metadata is the single source of truth for app and storage identity.
public enum SottoDuoBuild: Equatable, Sendable {
    case release, development

    // Unbundled Swift runs stay isolated from the installed app's preferences.
    public static let current: Self = Bundle.main.object(forInfoDictionaryKey: "SottoDuoDevelopmentBuild") as? Bool == false
        ? .release : .development

    public var displayName: String { self == .development ? "SottoDuo Dev" : "SottoDuo" }
    public var isDevelopment: Bool { self == .development }
    public var bundleIdentifier: String {
        self == .development ? "com.kristofferr.sottoduo.dev" : "com.kristofferr.sottoduo"
    }
    public var credentialService: String { bundleIdentifier + ".server" }
    public var windowAutosaveName: String { self == .development ? "SottoDuoDevMainWindow" : "SottoDuoMainWindow" }
    public var dataDirectory: URL {
        dataDirectory(in: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0])
    }
    func dataDirectory(in support: URL) -> URL {
        support.appendingPathComponent(displayName, isDirectory: true)
    }
}
