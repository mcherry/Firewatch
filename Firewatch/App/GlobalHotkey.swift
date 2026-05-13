import AppKit
import Carbon
import SwiftUI

// MARK: - KeyCombo

struct KeyCombo: Codable, Equatable {
    let keyCode: UInt32
    let carbonModifiers: UInt32

    /// Default shortcut: ⇧⌥S (Shift + Option + S)
    static let `default` = KeyCombo(
        keyCode: UInt32(kVK_ANSI_S),
        carbonModifiers: UInt32(shiftKey | optionKey)
    )

    init(keyCode: UInt32, carbonModifiers: UInt32) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
    }

    /// Initialize from an NSEvent, converting Cocoa modifier flags to Carbon modifiers.
    init(event: NSEvent) {
        self.keyCode = UInt32(event.keyCode)
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var mods: UInt32 = 0
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        self.carbonModifiers = mods
    }

    var hasModifiers: Bool {
        carbonModifiers != 0
    }

    var displayString: String {
        var result = ""
        // Standard macOS modifier order: ⌃⌥⇧⌘
        if carbonModifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        result += Self.keyName(for: keyCode)
        return result
    }

    private static func keyName(for code: UInt32) -> String {
        switch Int(code) {
        // Letters
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        // Numbers
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        // Function keys
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        // Special keys
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_Escape: return "⎋"
        // Arrow keys
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        // Navigation
        case kVK_Home: return "↖"
        case kVK_End: return "↘"
        case kVK_PageUp: return "⇞"
        case kVK_PageDown: return "⇟"
        // Punctuation
        case kVK_ANSI_Minus: return "-"
        case kVK_ANSI_Equal: return "="
        case kVK_ANSI_LeftBracket: return "["
        case kVK_ANSI_RightBracket: return "]"
        case kVK_ANSI_Backslash: return "\\"
        case kVK_ANSI_Semicolon: return ";"
        case kVK_ANSI_Quote: return "'"
        case kVK_ANSI_Comma: return ","
        case kVK_ANSI_Period: return "."
        case kVK_ANSI_Slash: return "/"
        case kVK_ANSI_Grave: return "`"
        default: return String(format: "0x%02X", code)
        }
    }
}

// MARK: - HotkeyManager

final class HotkeyManager {
    static let shared = HotkeyManager()

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var handler: (() -> Void)?
    private(set) var currentCombo: KeyCombo?

    private static let defaultsKey = "globalHotkeyCombo"
    private static let hotKeySignature: FourCharCode = 0x46574348 // "FWCH"

    private init() {
        installCarbonEventHandler()
    }

    deinit {
        unregister()
        if let ref = eventHandlerRef {
            RemoveEventHandler(ref)
        }
    }

    // MARK: Public

    func register(combo: KeyCombo, handler: @escaping () -> Void) {
        unregister()
        self.handler = handler

        var hotKeyID = EventHotKeyID(signature: Self.hotKeySignature, id: 1)
        let status = RegisterEventHotKey(
            combo.keyCode,
            combo.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if status == noErr {
            currentCombo = combo
            save(combo)
            NSLog("[Firewatch] Registered hotkey: %@", combo.displayString)
        } else {
            NSLog("[Firewatch] Failed to register hotkey: %d", status)
        }
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        currentCombo = nil
    }

    /// Re-register with a new combo, keeping the existing handler.
    func update(combo: KeyCombo) {
        guard let existingHandler = handler else { return }
        unregister()
        register(combo: combo, handler: existingHandler)
    }

    func clearShortcut() {
        unregister()
        UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
    }

    func loadSaved() -> KeyCombo? {
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
              let combo = try? JSONDecoder().decode(KeyCombo.self, from: data) else {
            return nil
        }
        return combo
    }

    // MARK: Private

    private func save(_ combo: KeyCombo) {
        if let data = try? JSONEncoder().encode(combo) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    private func installCarbonEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }

                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr else { return status }

                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                manager.handler?()
                return noErr
            },
            1,
            &eventType,
            selfPtr,
            &eventHandlerRef
        )
    }
}

// MARK: - ShortcutRecorderView

struct ShortcutRecorderView: View {
    var label: String = "Toggle Status Panel:"
    var onChange: ((KeyCombo?) -> Void)?

    @State private var isRecording = false
    @State private var currentCombo: KeyCombo?
    @State private var eventMonitor: Any?

    var body: some View {
        HStack {
            Text(label)
            Spacer()

            Button {
                if isRecording {
                    cancelRecording()
                } else {
                    startRecording()
                }
            } label: {
                Text(buttonLabel)
                    .foregroundStyle(isRecording ? .red : (currentCombo != nil ? .primary : .secondary))
                    .frame(minWidth: 90)
            }
            .buttonStyle(.bordered)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isRecording ? Color.accentColor : .clear, lineWidth: 2)
            )

            if currentCombo != nil && !isRecording {
                Button {
                    currentCombo = nil
                    onChange?(nil)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .onAppear {
            currentCombo = HotkeyManager.shared.currentCombo
        }
        .onDisappear {
            if isRecording { cancelRecording() }
        }
    }

    private var buttonLabel: String {
        if isRecording {
            return "Type shortcut…"
        } else if let combo = currentCombo {
            return combo.displayString
        } else {
            return "Record Shortcut"
        }
    }

    private func startRecording() {
        isRecording = true
        // Temporarily unregister so the existing hotkey doesn't
        // consume key events during recording
        HotkeyManager.shared.unregister()

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                cancelRecording()
                return nil
            }

            let combo = KeyCombo(event: event)
            if combo.hasModifiers {
                finishRecording(with: combo)
            }
            return nil
        }
    }

    private func finishRecording(with combo: KeyCombo) {
        removeMonitor()
        currentCombo = combo
        isRecording = false
        onChange?(combo)
    }

    private func cancelRecording() {
        removeMonitor()
        isRecording = false
        // Re-register the combo that was active before recording
        if let combo = currentCombo {
            HotkeyManager.shared.update(combo: combo)
        }
    }

    private func removeMonitor() {
        if let monitor = eventMonitor {
            eventMonitor = nil
            NSEvent.removeMonitor(monitor)
        }
    }
}
