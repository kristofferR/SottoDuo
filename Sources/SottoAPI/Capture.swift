import Foundation
import SottoAPIWire

public typealias AudioSourceIdentity = Components.Schemas.AudioSourceIdentity
public typealias AudioSource = Components.Schemas.AudioSource
public typealias AudioSourceList = Components.Schemas.AudioSourceList
public typealias RemoteCapture = Components.Schemas.RemoteCapture

extension AudioSourceList: APIWireModel { public typealias Wire = Self }

extension AudioSource {
    /// USB presence and transmitter link alone do not prove healthy audio.
    public func isEligible(at now: Date = Date()) -> Bool {
        let age = now.timeIntervalSince(observedAt)
        return age >= 0 && age <= 3.5 && present && capture == .available
            && (link == .connected || link == .notApplicable) && audioHealth != .degraded
    }
}

public enum CaptureMode: String, Codable, Sendable { case dictation, test }

public struct StartCaptureRequest: Codable, Sendable, APIWireModel {
    public typealias Wire = Components.Schemas.StartCaptureRequest
    public var requestID: UUID
    public var device: DeviceIdentity
    public var mode: CaptureMode
    public var source: AudioSourceIdentity

    public init(requestID: UUID, device: DeviceIdentity, mode: CaptureMode, source: AudioSourceIdentity) {
        self.requestID = requestID; self.device = device; self.mode = mode; self.source = source
    }
}

public struct StopCaptureRequest: Codable, Sendable, APIWireModel {
    public typealias Wire = Components.Schemas.StopCaptureRequest
    public var continuationID: UUID?
    public init(continuationID: UUID? = nil) { self.continuationID = continuationID }
}
