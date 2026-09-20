import Foundation

public enum RecognitionMode: String, Codable, CaseIterable, Sendable {
    case automatic, cloud, local
}

public struct RecognitionState: Codable, Equatable, Sendable {
    public enum Provider: String, Codable, Sendable { case soniox, whisper }
    public var provider: Provider
    public var fallbackReason: String?
    public var partialText: String?
    public init(provider: Provider, fallbackReason: String? = nil, partialText: String? = nil) {
        self.provider = provider
        self.fallbackReason = fallbackReason
        self.partialText = partialText
    }
}
