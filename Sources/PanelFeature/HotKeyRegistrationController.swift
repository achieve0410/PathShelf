import Carbon.HIToolbox
import Foundation

public enum HotKeyRegistrationError: Error, Equatable, CustomStringConvertible {
    case invalidBinding
    case alreadyRegistered
    case internalError
    case carbonStatus(OSStatus)
    case persistenceFailed(String)

    public init(status: OSStatus) {
        switch status {
        case OSStatus(eventHotKeyExistsErr):
            self = .alreadyRegistered
        case OSStatus(eventInternalErr):
            self = .internalError
        default:
            self = .carbonStatus(status)
        }
    }

    public var description: String {
        switch self {
        case .invalidBinding:
            return "Shortcut must include Command or Control."
        case .alreadyRegistered:
            return "Shortcut is already registered by another handler."
        case .internalError:
            return "Carbon hotkey registration returned an internal error."
        case .carbonStatus(let status):
            return "Carbon hotkey registration failed with OSStatus \(status)."
        case .persistenceFailed(let message):
            return "Shortcut registration succeeded but settings could not be saved: \(message)"
        }
    }
}

public final class HotKeyRegistrationController: @unchecked Sendable {
    public private(set) var activeBinding: ShortcutBinding?
    public private(set) var lastError: HotKeyRegistrationError?

    private var hotKeyRef: EventHotKeyRef?
    private let signature: OSType
    private let id: UInt32

    public init(signature: OSType = 0x4F465048, id: UInt32 = 1) {
        self.signature = signature
        self.id = id
    }

    deinit {
        unregister()
    }

    public func registerInitial(_ binding: ShortcutBinding) -> Result<Void, HotKeyRegistrationError> {
        apply(binding)
    }

    public func validateAndCommit(_ binding: ShortcutBinding) -> Result<Void, HotKeyRegistrationError> {
        if binding == activeBinding {
            lastError = nil
            return .success(())
        }

        return apply(binding)
    }

    public func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRef = nil
        activeBinding = nil
    }

    private func apply(_ binding: ShortcutBinding) -> Result<Void, HotKeyRegistrationError> {
        guard binding.isValidForGlobalRegistration else {
            lastError = .invalidBinding
            return .failure(.invalidBinding)
        }

        var candidateRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: signature, id: id)
        let status = RegisterEventHotKey(
            binding.keyCode,
            binding.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &candidateRef
        )

        guard status == noErr, let candidateRef else {
            let error = HotKeyRegistrationError(status: status)
            lastError = error
            return .failure(error)
        }

        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }

        hotKeyRef = candidateRef
        activeBinding = binding
        lastError = nil
        return .success(())
    }
}
