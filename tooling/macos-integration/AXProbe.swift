// AXProbe -- the macOS-layer probe behind `tooling/verify-macos-integration.mjs`.
//
// Why Swift and why AX: rows A1-A9 of the old physical-accessibility
// checklist describe macOS behavior -- what VoiceOver would speak, what a
// real keystroke does, which process actually owns a global shortcut.
// Chromium's DOM cannot see any of that. `ApplicationServices`
// (AXUIElement) and `CoreGraphics` (CGEvent) are the native homes of
// exactly those facts, and reading the AX tree reads the SAME data
// VoiceOver speaks -- without driving VoiceOver itself.
//
// Discipline this file must keep:
//   * It never guesses. Every command either produces the requested fact or
//     exits non-zero with a named reason on stderr.
//   * Missing Accessibility (TCC) permission is a NAMED FAILURE
//     (`accessibility_permission_denied`), never a silent degrade. The
//     runner turns that into a loud gate failure with the exact System
//     Settings path.
//   * It performs no build, no install, and no persistent system change.
//     `SystemSettings.swift` owns settings mutation, and it owns restore.

import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

// MARK: - Output

func emit(_ value: Any) {
  let data = try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
  FileHandle.standardOutput.write(data)
  FileHandle.standardOutput.write("\n".data(using: .utf8)!)
}

func die(_ reason: String, _ detail: String = "") -> Never {
  let suffix = detail.isEmpty ? "" : ": \(detail)"
  FileHandle.standardError.write("AXProbe \(reason)\(suffix)\n".data(using: .utf8)!)
  exit(2)
}

// MARK: - Arguments

var arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else {
  die("usage", "AXProbe <permission|frontmost|activate|dump|focused|selection|key|raise|windows>")
}
arguments = Array(arguments.dropFirst())

func option(_ name: String) -> String? {
  guard let index = arguments.firstIndex(of: "--\(name)"), index + 1 < arguments.count else { return nil }
  return arguments[index + 1]
}

func requiredOption(_ name: String) -> String {
  guard let value = option(name) else { die("missing_option", "--\(name)") }
  return value
}

func requiredPid() -> pid_t {
  guard let raw = Int32(requiredOption("pid")) else { die("invalid_option", "--pid must be an integer") }
  return raw
}

// MARK: - Permission

/// Never prompts. A prompt would block a non-interactive gate run forever,
/// and the runner needs a deterministic answer it can turn into an
/// actionable failure.
func isTrusted() -> Bool {
  let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
  return AXIsProcessTrustedWithOptions(options)
}

/// The process TCC actually attributes an Accessibility grant to is the
/// RESPONSIBLE process -- usually the terminal/host application that
/// launched this binary, not this binary. Reporting the whole ancestry
/// makes the grant instruction actionable instead of a guess.
func processAncestry() -> [[String: Any]] {
  var chain: [[String: Any]] = []
  var pid = getpid()
  for _ in 0..<8 {
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.stride
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
    guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { break }
    let name = withUnsafePointer(to: info.kp_proc.p_comm) {
      $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN) + 1) { String(cString: $0) }
    }
    chain.append(["name": name, "pid": Int(pid)])
    let parent = info.kp_eproc.e_ppid
    if parent <= 1 || parent == pid { break }
    pid = parent
  }
  return chain
}

func requireTrusted() {
  if isTrusted() { return }
  let names = processAncestry().map { ($0["name"] as? String) ?? "?" }.joined(separator: " <- ")
  die("accessibility_permission_denied", "process chain: \(names)")
}

// MARK: - AX helpers

func axValue(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
  var value: CFTypeRef?
  let status = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
  if status == .apiDisabled { die("accessibility_permission_denied", "AXUIElement API is disabled for this process") }
  guard status == .success else { return nil }
  return value
}

func axString(_ element: AXUIElement, _ attribute: String) -> String? {
  guard let value = axValue(element, attribute) else { return nil }
  if let text = value as? String { return text }
  if CFGetTypeID(value) == AXValueGetTypeID() { return nil }
  if let number = value as? NSNumber { return number.stringValue }
  return nil
}

func axBool(_ element: AXUIElement, _ attribute: String) -> Bool? {
  guard let value = axValue(element, attribute), let number = value as? NSNumber else { return nil }
  return number.boolValue
}

func axChildren(_ element: AXUIElement) -> [AXUIElement] {
  guard let value = axValue(element, kAXChildrenAttribute as String) else { return [] }
  return (value as? [AXUIElement]) ?? []
}

func axFrame(_ element: AXUIElement) -> [String: Double]? {
  guard
    let positionValue = axValue(element, kAXPositionAttribute as String),
    let sizeValue = axValue(element, kAXSizeAttribute as String),
    CFGetTypeID(positionValue) == AXValueGetTypeID(),
    CFGetTypeID(sizeValue) == AXValueGetTypeID()
  else { return nil }
  var point = CGPoint.zero
  var size = CGSize.zero
  AXValueGetValue(positionValue as! AXValue, .cgPoint, &point)
  AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
  return ["height": size.height, "width": size.width, "x": point.x, "y": point.y]
}

func describe(_ element: AXUIElement) -> [String: Any] {
  var node: [String: Any] = [:]
  node["role"] = axString(element, kAXRoleAttribute as String) ?? ""
  if let subrole = axString(element, kAXSubroleAttribute as String) { node["subrole"] = subrole }
  if let title = axString(element, kAXTitleAttribute as String) { node["title"] = title }
  if let value = axString(element, kAXValueAttribute as String) { node["value"] = value }
  if let description = axString(element, kAXDescriptionAttribute as String) { node["description"] = description }
  if let help = axString(element, kAXHelpAttribute as String) { node["help"] = help }
  if let identifier = axString(element, "AXDOMIdentifier") { node["domIdentifier"] = identifier }
  if let identifier = axString(element, kAXIdentifierAttribute as String) { node["identifier"] = identifier }
  if let roleDescription = axString(element, kAXRoleDescriptionAttribute as String) { node["roleDescription"] = roleDescription }
  // `aria-current` is how the workspace marks the SELECTED task, which D-05
  // requires to stay distinguishable from wherever roving/VoiceOver focus
  // currently is. Chromium surfaces it as AXARIACurrent.
  if let current = axString(element, "AXARIACurrent") { node["ariaCurrent"] = current }
  if let live = axString(element, "AXARIALive") { node["ariaLive"] = live }
  if let selected = axBool(element, kAXSelectedAttribute as String) { node["selected"] = selected }
  if let focused = axBool(element, kAXFocusedAttribute as String) { node["focused"] = focused }
  if let enabled = axBool(element, kAXEnabledAttribute as String) { node["enabled"] = enabled }
  if let frame = axFrame(element) { node["frame"] = frame }
  return node
}

func tree(_ element: AXUIElement, depth: Int, budget: inout Int) -> [String: Any] {
  var node = describe(element)
  budget -= 1
  if depth <= 0 || budget <= 0 { return node }
  var children: [[String: Any]] = []
  for child in axChildren(element) {
    if budget <= 0 { break }
    children.append(tree(child, depth: depth - 1, budget: &budget))
  }
  if !children.isEmpty { node["children"] = children }
  return node
}

/// Chromium/Electron only publishes its web-content accessibility tree once
/// an assistive client asks for it. VoiceOver does that by setting
/// `AXEnhancedUserInterface`; Electron additionally honours
/// `AXManualAccessibility`. Setting both is what makes the AX tree this
/// probe reads the SAME tree VoiceOver would speak.
func activateAccessibility(_ application: AXUIElement) {
  let yes = kCFBooleanTrue as CFTypeRef
  AXUIElementSetAttributeValue(application, "AXManualAccessibility" as CFString, yes)
  AXUIElementSetAttributeValue(application, "AXEnhancedUserInterface" as CFString, yes)
  // Chromium builds (or rebuilds) its accessibility tree asynchronously once
  // asked. Querying in the same instant returns a half-populated tree, which
  // would make this lane intermittently report a real element as absent --
  // exactly the kind of flake that erodes trust in a gate. Settle, then poll
  // until the focused-element attribute is answerable.
  usleep(120_000)
}

/// Reads the focused element, tolerating the accessibility tree still coming
/// up. Returns nil only when the application genuinely reports no focus.
func focusedUIElement(_ application: AXUIElement, attempts: Int = 12) -> AXUIElement? {
  for attempt in 0..<attempts {
    if let raw = axValue(application, kAXFocusedUIElementAttribute as String) {
      return (raw as! AXUIElement)
    }
    if attempt + 1 < attempts { usleep(120_000) }
  }
  return nil
}

// MARK: - Keyboard

let namedKeyCodes: [String: CGKeyCode] = [
  "a": 0, "b": 11, "c": 8, "d": 2, "e": 14, "f": 3, "g": 5, "h": 4, "i": 34, "j": 38,
  "k": 40, "l": 37, "m": 46, "n": 45, "o": 31, "p": 35, "q": 12, "r": 15, "s": 1,
  "t": 17, "u": 32, "v": 9, "w": 13, "x": 7, "y": 16, "z": 6,
  "0": 29, "1": 18, "2": 19, "3": 20, "4": 21, "5": 23, "6": 22, "7": 26, "8": 28, "9": 25,
  "return": 36, "enter": 36, "tab": 48, "space": 49, "delete": 51, "escape": 53,
  "left": 123, "right": 124, "down": 125, "up": 126,
  "semicolon": 41, "quote": 39, "comma": 43, "period": 47, "slash": 44, "minus": 27,
  "equal": 24, "leftbracket": 33, "rightbracket": 30, "backslash": 42, "grave": 50,
  "f5": 96,
]

let modifierFlags: [String: CGEventFlags] = [
  "cmd": .maskCommand, "command": .maskCommand,
  "shift": .maskShift,
  "alt": .maskAlternate, "option": .maskAlternate,
  "ctrl": .maskControl, "control": .maskControl,
  "fn": .maskSecondaryFn,
]

let eventSource = CGEventSource(stateID: .hidSystemState)

func postKeyCode(_ keyCode: CGKeyCode, flags: CGEventFlags) {
  guard
    let down = CGEvent(keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: true),
    let up = CGEvent(keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: false)
  else { die("cgevent_creation_failed", "key code \(keyCode)") }
  down.flags = flags
  up.flags = flags
  down.post(tap: .cghidEventTap)
  up.post(tap: .cghidEventTap)
}

/// Shifted US-layout characters that have a plain virtual key code. Typing
/// through REAL virtual key codes (rather than only unicode payloads) keeps
/// `text:` on the same event path a physical keyboard uses, which is the
/// whole point of this lane.
let shiftedCharacters: [Character: String] = [
  "!": "1", "@": "2", "#": "3", "$": "4", "%": "5", "^": "6", "&": "7", "*": "8",
  "(": "9", ")": "0", "_": "minus", "+": "equal", "{": "leftbracket", "}": "rightbracket",
  ":": "semicolon", "\"": "quote", "<": "comma", ">": "period", "?": "slash",
  "|": "backslash", "~": "grave",
]

let plainCharacters: [Character: String] = [
  "-": "minus", "=": "equal", "[": "leftbracket", "]": "rightbracket", ";": "semicolon",
  "'": "quote", ",": "comma", ".": "period", "/": "slash", "\\": "backslash", "`": "grave",
  " ": "space",
]

func postUnicodeCharacter(_ character: Character) {
  let utf16 = Array(String(character).utf16)
  guard
    let down = CGEvent(keyboardEventSource: eventSource, virtualKey: 0, keyDown: true),
    let up = CGEvent(keyboardEventSource: eventSource, virtualKey: 0, keyDown: false)
  else { die("cgevent_creation_failed", "unicode \(character)") }
  down.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
  up.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
  down.post(tap: .cghidEventTap)
  up.post(tap: .cghidEventTap)
}

func postUnicode(_ text: String) {
  for character in text {
    if let name = plainCharacters[character], let code = namedKeyCodes[name] {
      postKeyCode(code, flags: [])
    } else if let name = shiftedCharacters[character], let code = namedKeyCodes[name] {
      postKeyCode(code, flags: .maskShift)
    } else if character.isUppercase, let code = namedKeyCodes[character.lowercased()] {
      postKeyCode(code, flags: .maskShift)
    } else if let code = namedKeyCodes[String(character)] {
      postKeyCode(code, flags: [])
    } else {
      postUnicodeCharacter(character)
    }
    usleep(14_000)
  }
}

/// One step of a `--sequence`. Forms:
///   `tab`, `cmd+n`, `shift+tab`      -- named key with optional modifiers
///   `code:33`                        -- RAW virtual key code. Essential for
///                                       A7: the OS translates a raw code
///                                       through the ACTIVE input source, so
///                                       a dead-key sequence composes for
///                                       real instead of being faked.
///   `text:hello world`               -- literal unicode insertion
///   `wait:250`                       -- milliseconds
func performStep(_ step: String) {
  if step.hasPrefix("text:") {
    postUnicode(String(step.dropFirst("text:".count)))
    return
  }
  if step.hasPrefix("wait:") {
    let milliseconds = UInt32(step.dropFirst("wait:".count)) ?? 0
    usleep(milliseconds * 1_000)
    return
  }
  var flags = CGEventFlags()
  var keyToken = step
  if step.contains("+") {
    let parts = step.split(separator: "+").map(String.init)
    keyToken = parts.last ?? ""
    for modifier in parts.dropLast() {
      guard let flag = modifierFlags[modifier.lowercased()] else { die("unknown_modifier", modifier) }
      flags.insert(flag)
    }
  }
  if keyToken.hasPrefix("code:") {
    guard let raw = UInt16(keyToken.dropFirst("code:".count)) else { die("invalid_key_code", keyToken) }
    postKeyCode(CGKeyCode(raw), flags: flags)
    usleep(12_000)
    return
  }
  guard let keyCode = namedKeyCodes[keyToken.lowercased()] else { die("unknown_key", keyToken) }
  postKeyCode(keyCode, flags: flags)
  usleep(12_000)
}

// MARK: - Commands

switch command {
case "attributes":
  requireTrusted()
  let pid = requiredPid()
  let application = AXUIElementCreateApplication(pid)
  activateAccessibility(application)
  guard let element = focusedUIElement(application) else { die("no_focused_element") }
  var names: CFArray?
  AXUIElementCopyAttributeNames(element, &names)
  emit(["attributes": (names as? [String]) ?? []])

case "permission":
  emit(["ancestry": processAncestry(), "trusted": isTrusted()])

case "frontmost":
  requireTrusted()
  guard let application = NSWorkspace.shared.frontmostApplication else { die("no_frontmost_application") }
  emit([
    "bundleIdentifier": application.bundleIdentifier ?? "",
    "name": application.localizedName ?? "",
    "pid": Int(application.processIdentifier),
  ])

case "raise":
  requireTrusted()
  let pid = requiredPid()
  guard let application = NSRunningApplication(processIdentifier: pid) else { die("no_such_process", "\(pid)") }
  let activated = application.activate(options: [.activateAllWindows])
  usleep(400_000)
  emit(["activated": activated, "pid": Int(pid)])

case "activate":
  requireTrusted()
  let pid = requiredPid()
  activateAccessibility(AXUIElementCreateApplication(pid))
  usleep(400_000)
  emit(["activated": true, "pid": Int(pid)])

case "windows":
  requireTrusted()
  let pid = requiredPid()
  let application = AXUIElementCreateApplication(pid)
  activateAccessibility(application)
  let windows = axChildren(application).filter { (axString($0, kAXRoleAttribute as String) ?? "") == "AXWindow" }
  emit(["windows": windows.map { describe($0) }])

case "dump":
  requireTrusted()
  let pid = requiredPid()
  let depth = Int(option("depth") ?? "24") ?? 24
  var budget = Int(option("max-nodes") ?? "4000") ?? 4000
  let application = AXUIElementCreateApplication(pid)
  activateAccessibility(application)
  emit(["pid": Int(pid), "tree": tree(application, depth: depth, budget: &budget)])

case "focused":
  requireTrusted()
  let pid = requiredPid()
  let application = AXUIElementCreateApplication(pid)
  activateAccessibility(application)
  guard let element = focusedUIElement(application) else {
    emit(["focused": NSNull()])
    break
  }
  var node = describe(element)
  // The parent chain is how a row like A6 proves focus landed on something
  // real and reachable, not on a detached or application-level element.
  var ancestors: [[String: Any]] = []
  var cursor: AXUIElement? = element
  for _ in 0..<12 {
    guard let current = cursor, let parentRaw = axValue(current, kAXParentAttribute as String) else { break }
    let parent = parentRaw as! AXUIElement
    ancestors.append(describe(parent))
    cursor = parent
  }
  node["ancestors"] = ancestors
  emit(["focused": node])

case "selection":
  requireTrusted()
  let pid = requiredPid()
  let application = AXUIElementCreateApplication(pid)
  activateAccessibility(application)
  guard let element = focusedUIElement(application) else {
    emit(["selection": NSNull()])
    break
  }
  var payload: [String: Any] = ["value": axString(element, kAXValueAttribute as String) ?? ""]
  if let rangeValue = axValue(element, kAXSelectedTextRangeAttribute as String), CFGetTypeID(rangeValue) == AXValueGetTypeID() {
    var range = CFRange(location: -1, length: -1)
    AXValueGetValue(rangeValue as! AXValue, .cfRange, &range)
    payload["location"] = range.location
    payload["length"] = range.length
  }
  if let selectedText = axString(element, kAXSelectedTextAttribute as String) { payload["selectedText"] = selectedText }
  emit(["selection": payload])

case "key":
  requireTrusted()
  let sequence = requiredOption("sequence")
  let steps = sequence.split(separator: ",").map(String.init).filter { !$0.isEmpty }
  if steps.isEmpty { die("empty_sequence") }
  for step in steps { performStep(step) }
  emit(["posted": steps.count])

default:
  die("unknown_command", command)
}
