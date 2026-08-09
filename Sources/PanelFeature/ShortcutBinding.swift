import Foundation
import Carbon.HIToolbox

public struct ShortcutBinding: Codable, Equatable, Sendable {
    public enum Modifier: String, Codable, CaseIterable, Sendable {
        case command
        case control
        case option
        case shift
    }

    public var keyCode: UInt32
    public var modifiers: Set<Modifier>

    public init(keyCode: UInt32, modifiers: Set<Modifier>) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public static let `default` = ShortcutBinding(
        keyCode: UInt32(kVK_ANSI_O),
        modifiers: [.command, .control]
    )

    public var isValidForGlobalRegistration: Bool {
        modifiers.contains(.command) || modifiers.contains(.control)
    }

    public var carbonModifiers: UInt32 {
        var value: UInt32 = 0
        if modifiers.contains(.command) {
            value |= UInt32(cmdKey)
        }
        if modifiers.contains(.control) {
            value |= UInt32(controlKey)
        }
        if modifiers.contains(.option) {
            value |= UInt32(optionKey)
        }
        if modifiers.contains(.shift) {
            value |= UInt32(shiftKey)
        }
        return value
    }
}
