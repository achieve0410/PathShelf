import Carbon.HIToolbox
import Foundation

public struct ShortcutKeyChoice: Codable, Equatable, Identifiable, Sendable {
    public var displayName: String
    public var keyCode: UInt32

    public var id: UInt32 { keyCode }

    public init(displayName: String, keyCode: UInt32) {
        self.displayName = displayName
        self.keyCode = keyCode
    }

    public static let supported: [ShortcutKeyChoice] = [
        ShortcutKeyChoice(displayName: "A", keyCode: UInt32(kVK_ANSI_A)),
        ShortcutKeyChoice(displayName: "B", keyCode: UInt32(kVK_ANSI_B)),
        ShortcutKeyChoice(displayName: "C", keyCode: UInt32(kVK_ANSI_C)),
        ShortcutKeyChoice(displayName: "D", keyCode: UInt32(kVK_ANSI_D)),
        ShortcutKeyChoice(displayName: "E", keyCode: UInt32(kVK_ANSI_E)),
        ShortcutKeyChoice(displayName: "F", keyCode: UInt32(kVK_ANSI_F)),
        ShortcutKeyChoice(displayName: "G", keyCode: UInt32(kVK_ANSI_G)),
        ShortcutKeyChoice(displayName: "H", keyCode: UInt32(kVK_ANSI_H)),
        ShortcutKeyChoice(displayName: "I", keyCode: UInt32(kVK_ANSI_I)),
        ShortcutKeyChoice(displayName: "J", keyCode: UInt32(kVK_ANSI_J)),
        ShortcutKeyChoice(displayName: "K", keyCode: UInt32(kVK_ANSI_K)),
        ShortcutKeyChoice(displayName: "L", keyCode: UInt32(kVK_ANSI_L)),
        ShortcutKeyChoice(displayName: "M", keyCode: UInt32(kVK_ANSI_M)),
        ShortcutKeyChoice(displayName: "N", keyCode: UInt32(kVK_ANSI_N)),
        ShortcutKeyChoice(displayName: "O", keyCode: UInt32(kVK_ANSI_O)),
        ShortcutKeyChoice(displayName: "P", keyCode: UInt32(kVK_ANSI_P)),
        ShortcutKeyChoice(displayName: "Q", keyCode: UInt32(kVK_ANSI_Q)),
        ShortcutKeyChoice(displayName: "R", keyCode: UInt32(kVK_ANSI_R)),
        ShortcutKeyChoice(displayName: "S", keyCode: UInt32(kVK_ANSI_S)),
        ShortcutKeyChoice(displayName: "T", keyCode: UInt32(kVK_ANSI_T)),
        ShortcutKeyChoice(displayName: "U", keyCode: UInt32(kVK_ANSI_U)),
        ShortcutKeyChoice(displayName: "V", keyCode: UInt32(kVK_ANSI_V)),
        ShortcutKeyChoice(displayName: "W", keyCode: UInt32(kVK_ANSI_W)),
        ShortcutKeyChoice(displayName: "X", keyCode: UInt32(kVK_ANSI_X)),
        ShortcutKeyChoice(displayName: "Y", keyCode: UInt32(kVK_ANSI_Y)),
        ShortcutKeyChoice(displayName: "Z", keyCode: UInt32(kVK_ANSI_Z)),
        ShortcutKeyChoice(displayName: "0", keyCode: UInt32(kVK_ANSI_0)),
        ShortcutKeyChoice(displayName: "1", keyCode: UInt32(kVK_ANSI_1)),
        ShortcutKeyChoice(displayName: "2", keyCode: UInt32(kVK_ANSI_2)),
        ShortcutKeyChoice(displayName: "3", keyCode: UInt32(kVK_ANSI_3)),
        ShortcutKeyChoice(displayName: "4", keyCode: UInt32(kVK_ANSI_4)),
        ShortcutKeyChoice(displayName: "5", keyCode: UInt32(kVK_ANSI_5)),
        ShortcutKeyChoice(displayName: "6", keyCode: UInt32(kVK_ANSI_6)),
        ShortcutKeyChoice(displayName: "7", keyCode: UInt32(kVK_ANSI_7)),
        ShortcutKeyChoice(displayName: "8", keyCode: UInt32(kVK_ANSI_8)),
        ShortcutKeyChoice(displayName: "9", keyCode: UInt32(kVK_ANSI_9)),
        ShortcutKeyChoice(displayName: "Space", keyCode: UInt32(kVK_Space))
    ]

    public static func choice(for keyCode: UInt32) -> ShortcutKeyChoice {
        supported.first { $0.keyCode == keyCode } ?? ShortcutKeyChoice(displayName: "O", keyCode: UInt32(kVK_ANSI_O))
    }
}
