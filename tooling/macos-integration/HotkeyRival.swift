// HotkeyRival -- a deliberate competitor for Keepling's Quick Entry global
// accelerator.
//
// Row A8 is about REAL operating-system arbitration: when two applications
// ask for the same global shortcut, exactly one gets it, and the loser must
// know it lost. No test harness can synthesize that, because the arbitration
// happens in the window server, not in either application. So this binary is
// a real, separate process that really registers the same accelerator
// through the same Carbon API Electron's `globalShortcut` uses.
//
// It is deliberately tiny and short-lived: it registers, reports honestly
// whether registration succeeded, prints a line every time the OS delivers
// the hotkey to IT rather than to Keepling, and unregisters and exits on
// SIGTERM/SIGINT.

import AppKit
import Carbon
import Foundation

func line(_ text: String) {
  FileHandle.standardOutput.write("\(text)\n".data(using: .utf8)!)
}

var arguments = Array(CommandLine.arguments.dropFirst())
func option(_ name: String) -> String? {
  guard let index = arguments.firstIndex(of: "--\(name)"), index + 1 < arguments.count else { return nil }
  return arguments[index + 1]
}

// Defaults match Keepling's shipped Quick Entry accelerator
// (Control+Alt+Space) so the collision is genuine rather than arranged.
let keyCode = UInt32(option("key-code").flatMap { UInt32($0) } ?? 49)
let wantsControl = option("modifiers")?.contains("control") ?? true
let wantsOption = option("modifiers")?.contains("option") ?? true
let wantsShift = option("modifiers")?.contains("shift") ?? false
let wantsCommand = option("modifiers")?.contains("command") ?? false

var modifiers: UInt32 = 0
if wantsControl { modifiers |= UInt32(controlKey) }
if wantsOption { modifiers |= UInt32(optionKey) }
if wantsShift { modifiers |= UInt32(shiftKey) }
if wantsCommand { modifiers |= UInt32(cmdKey) }

var hotKeyReference: EventHotKeyRef?
var identifier = EventHotKeyID(signature: OSType(0x4B_50_4C_52), id: 1) // 'KPLR'

var handlerReference: EventHandlerRef?
var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

let callback: EventHandlerUPP = { _, _, _ -> OSStatus in
  line("RIVAL received=1")
  return noErr
}
InstallEventHandler(GetApplicationEventTarget(), callback, 1, &eventType, nil, &handlerReference)

let status = RegisterEventHotKey(keyCode, modifiers, identifier, GetApplicationEventTarget(), 0, &hotKeyReference)
// `eventHotKeyExistsErr` is not an error condition for this program: it IS
// the observation row A8 exists to make. Report it honestly and keep running
// so the runner can still see who the OS delivers the key to.
line("RIVAL registered=\(status == noErr) status=\(status)")

func shutDown() -> Never {
  if let hotKeyReference { UnregisterEventHotKey(hotKeyReference) }
  if let handlerReference { RemoveEventHandler(handlerReference) }
  line("RIVAL released=1")
  exit(0)
}

// Retained for the process lifetime: a signal source that goes out of scope
// stops firing, which would leave a rival holding a global shortcut on
// someone's machine.
var signalSources: [DispatchSourceSignal] = []
for signalNumber in [SIGTERM, SIGINT] {
  signal(signalNumber, SIG_IGN)
  let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
  source.setEventHandler { shutDown() }
  source.resume()
  signalSources.append(source)
}

// A hard ceiling so a forgotten rival can never keep holding a global
// shortcut on someone's machine.
DispatchQueue.main.asyncAfter(deadline: .now() + 300) { shutDown() }

// A plain command-line process has no window-server connection, and Carbon
// hot-key events are delivered to the APPLICATION event target -- so without
// this the rival would register successfully and then never observe the key
// it won. `.accessory` keeps it out of the Dock and the menu bar while still
// making it a real application as far as the OS is concerned.
let application = NSApplication.shared
application.setActivationPolicy(.accessory)
application.run()
