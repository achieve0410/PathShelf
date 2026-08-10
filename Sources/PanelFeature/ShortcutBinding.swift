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

    private enum CodingKeys: String, CodingKey {
        case keyCode
        case modifiers
    }

    public init(keyCode: UInt32, modifiers: Set<Modifier>) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keyCode = try container.decode(UInt32.self, forKey: .keyCode)
        modifiers = Set(
            try container.decode([Modifier].self, forKey: .modifiers)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(keyCode, forKey: .keyCode)
        try container.encode(
            Modifier.allCases.filter(modifiers.contains),
            forKey: .modifiers
        )
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
