// SystemSettings -- real macOS system settings, captured before mutation and
// restorable on every exit path.
//
// Rows A5-A7 and A10-A15 are about the OS, not about a CSS media query
// emulation. Full Keyboard Access, a non-US dead-key input source, Increase
// Contrast, Differentiate Without Color, Reduce Transparency, Reduce Motion
// and the Light/Dark appearance are all real user-visible settings, and this
// binary is the only thing in the repository allowed to change them.
//
// SAFETY CONTRACT (this runs on a person's own Mac):
//   * `capture` reads every managed setting and prints it. The Node runner
//     writes that capture to disk BEFORE any mutation and restores from it on
//     success, failure, exception, SIGINT and SIGTERM.
//   * `apply` only ever writes keys from the managed, closed vocabulary
//     below. There is no free-form "write any default" command, because a
//     restore can only be trusted if the set of things that can change is
//     bounded.
//   * Restoration is verified by re-reading, never assumed.

import AppKit
import Carbon
import CoreGraphics
import Foundation
import ScreenCaptureKit

func emit(_ value: Any) {
  let data = try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
  FileHandle.standardOutput.write(data)
  FileHandle.standardOutput.write("\n".data(using: .utf8)!)
}

func die(_ reason: String, _ detail: String = "") -> Never {
  let suffix = detail.isEmpty ? "" : ": \(detail)"
  FileHandle.standardError.write("SystemSettings \(reason)\(suffix)\n".data(using: .utf8)!)
  exit(2)
}

var arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else {
  die("usage", "SystemSettings <capture|apply|screen-permission|capture-window|contrast|input-sources|select-input-source>")
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

// MARK: - Managed settings (closed vocabulary)

enum SettingKind { case boolean, integer, string }

struct ManagedSetting {
  let name: String
  let domain: String
  let key: String
  let kind: SettingKind
  /// Distributed notifications that make a RUNNING application observe the
  /// change instead of only picking it up at next launch.
  let notifications: [String]
}

let GLOBAL_DOMAIN = "Apple Global Domain"
let UNIVERSAL_ACCESS = "com.apple.universalaccess"

let managedSettings: [ManagedSetting] = [
  ManagedSetting(name: "fullKeyboardAccess", domain: GLOBAL_DOMAIN, key: "AppleKeyboardUIMode", kind: .integer,
                 notifications: ["com.apple.KeyboardUIModeDidChange", "AppleKeyboardUIModeChanged"]),
  ManagedSetting(name: "increaseContrast", domain: UNIVERSAL_ACCESS, key: "increaseContrast", kind: .boolean,
                 notifications: ["com.apple.universalaccess.increaseContrastChanged", "AXInterfaceIncreaseContrastDidChange"]),
  ManagedSetting(name: "differentiateWithoutColor", domain: UNIVERSAL_ACCESS, key: "differentiateWithoutColor", kind: .boolean,
                 notifications: ["com.apple.universalaccess.differentiateWithoutColorChanged"]),
  ManagedSetting(name: "reduceTransparency", domain: UNIVERSAL_ACCESS, key: "reduceTransparency", kind: .boolean,
                 notifications: ["com.apple.universalaccess.reduceTransparencyChanged", "AXInterfaceReduceTransparencyDidChange"]),
  ManagedSetting(name: "reduceMotion", domain: UNIVERSAL_ACCESS, key: "reduceMotion", kind: .boolean,
                 notifications: ["com.apple.universalaccess.reduceMotionChanged", "AXInterfaceReduceMotionDidChange"]),
  ManagedSetting(name: "appearance", domain: GLOBAL_DOMAIN, key: "AppleInterfaceStyle", kind: .string,
                 notifications: ["AppleInterfaceThemeChangedNotification"]),
]

func setting(named name: String) -> ManagedSetting {
  guard let match = managedSettings.first(where: { $0.name == name }) else {
    die("unmanaged_setting", "\(name) is not in the closed managed vocabulary, so it could not be restored")
  }
  return match
}

func readSetting(_ managed: ManagedSetting) -> Any {
  let value = CFPreferencesCopyAppValue(managed.key as CFString, managed.domain as CFString)
  guard let value else { return NSNull() }
  switch managed.kind {
  case .boolean: return (value as? NSNumber)?.boolValue ?? NSNull()
  case .integer: return (value as? NSNumber)?.intValue ?? NSNull()
  case .string: return (value as? String) ?? NSNull()
  }
}

func writeSetting(_ managed: ManagedSetting, _ value: Any) {
  if value is NSNull {
    CFPreferencesSetAppValue(managed.key as CFString, nil, managed.domain as CFString)
  } else {
    switch managed.kind {
    case .boolean:
      let flag = (value as? NSNumber)?.boolValue ?? false
      CFPreferencesSetAppValue(managed.key as CFString, flag as CFBoolean, managed.domain as CFString)
    case .integer:
      let number = (value as? NSNumber)?.intValue ?? 0
      CFPreferencesSetAppValue(managed.key as CFString, number as CFNumber, managed.domain as CFString)
    case .string:
      CFPreferencesSetAppValue(managed.key as CFString, (value as? String) as CFString?, managed.domain as CFString)
    }
  }
  CFPreferencesAppSynchronize(managed.domain as CFString)
  let center = DistributedNotificationCenter.default()
  for name in managed.notifications {
    center.postNotificationName(Notification.Name(name), object: nil, userInfo: nil, deliverImmediately: true)
  }
}

// MARK: - Input sources

func inputSourceProperty(_ source: TISInputSource, _ key: CFString) -> String {
  guard let pointer = TISGetInputSourceProperty(source, key) else { return "" }
  return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
}
func inputSourceFlag(_ source: TISInputSource, _ key: CFString) -> Bool {
  guard let pointer = TISGetInputSourceProperty(source, key) else { return false }
  return (Unmanaged<CFBoolean>.fromOpaque(pointer).takeUnretainedValue() as? Bool) ?? false
}

func keyboardLayouts() -> [TISInputSource] {
  let filter = [kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as Any] as CFDictionary
  guard let list = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource] else { return [] }
  return list.filter { inputSourceProperty($0, kTISPropertyInputSourceType) == (kTISTypeKeyboardLayout as String) }
}

func layout(withIdentifier identifier: String) -> TISInputSource? {
  keyboardLayouts().first { inputSourceProperty($0, kTISPropertyInputSourceID) == identifier }
}

// MARK: - Pixels

func requireScreenCapture() {
  if CGPreflightScreenCaptureAccess() { return }
  die(
    "screen_recording_permission_denied",
    "grant Screen Recording in System Settings -> Privacy & Security -> Screen Recording to the process running this lane"
  )
}

/// Captures the on-screen pixels of an application's window through
/// ScreenCaptureKit (`CGWindowListCreateImage` was removed in macOS 15).
/// Legibility rows assert a COMPUTED contrast ratio over these pixels rather
/// than a human impression of "looks fine".
func captureWindowImage(pid: pid_t) -> CGImage {
  requireScreenCapture()
  let semaphore = DispatchSemaphore(value: 0)
  var captured: CGImage?
  var failure: String?

  Task {
    do {
      let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
      let windows = content.windows.filter { window in
        window.owningApplication?.processID == pid && (window.frame.height > 200)
      }
      guard let window = windows.max(by: { $0.frame.height * $0.frame.width < $1.frame.height * $1.frame.width }) else {
        failure = "no_capturable_window: pid \(pid)"
        semaphore.signal()
        return
      }
      let filter = SCContentFilter(desktopIndependentWindow: window)
      let configuration = SCStreamConfiguration()
      configuration.width = Int(window.frame.width * 2)
      configuration.height = Int(window.frame.height * 2)
      configuration.showsCursor = false
      captured = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    } catch {
      failure = "window_capture_failed: \(error.localizedDescription)"
    }
    semaphore.signal()
  }

  if semaphore.wait(timeout: .now() + 30) == .timedOut { die("window_capture_timeout", "pid \(pid)") }
  if let failure { die(failure, "") }
  guard let image = captured else { die("window_capture_failed", "pid \(pid)") }
  if image.width < 50 || image.height < 50 { die("window_capture_empty", "pid \(pid)") }
  return image
}

struct Pixel: Hashable { let r: UInt8; let g: UInt8; let b: UInt8 }

func relativeLuminance(_ pixel: Pixel) -> Double {
  func channel(_ raw: UInt8) -> Double {
    let value = Double(raw) / 255.0
    return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
  }
  return 0.2126 * channel(pixel.r) + 0.7152 * channel(pixel.g) + 0.0722 * channel(pixel.b)
}

func contrastRatio(_ left: Pixel, _ right: Pixel) -> Double {
  let a = relativeLuminance(left)
  let b = relativeLuminance(right)
  return (max(a, b) + 0.05) / (min(a, b) + 0.05)
}

/// Reduces a window capture to the WCAG contrast between its dominant
/// (background) colour and the most prevalent clearly-different colour --
/// in practice, the body text. A window that has gone invisible or
/// washed-out collapses this ratio, which is exactly what A10/A12 claim
/// must not happen.
func analyseContrast(_ image: CGImage) -> [String: Any] {
  let width = image.width
  let height = image.height
  var raw = [UInt8](repeating: 0, count: width * height * 4)
  let colorSpace = CGColorSpaceCreateDeviceRGB()
  guard let context = CGContext(
    data: &raw, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
    space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
  ) else { die("bitmap_context_failed") }
  context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

  var histogram: [Pixel: Int] = [:]
  var index = 0
  while index + 3 < raw.count {
    histogram[Pixel(r: raw[index], g: raw[index + 1], b: raw[index + 2]), default: 0] += 1
    index += 4
  }
  guard let background = histogram.max(by: { $0.value < $1.value })?.key else { die("empty_capture") }

  var bestRatio = 1.0
  var bestPixel = background
  var distinctColours = 0
  for (pixel, count) in histogram {
    // Ignore near-singleton colours: antialiasing edges are not "content",
    // and letting one stray pixel supply the ratio would make this a
    // meaningless always-pass measurement.
    if count < max(64, (width * height) / 20_000) { continue }
    distinctColours += 1
    let ratio = contrastRatio(background, pixel)
    if ratio > bestRatio {
      bestRatio = ratio
      bestPixel = pixel
    }
  }
  return [
    "backgroundColour": ["b": Int(background.b), "g": Int(background.g), "r": Int(background.r)],
    "bestRatio": bestRatio,
    "distinctSignificantColours": distinctColours,
    "foregroundColour": ["b": Int(bestPixel.b), "g": Int(bestPixel.g), "r": Int(bestPixel.r)],
    "height": height,
    "width": width,
  ]
}

// MARK: - Commands

switch command {
case "capture":
  var payload: [String: Any] = [:]
  for managed in managedSettings { payload[managed.name] = readSetting(managed) }
  var inputSource: [String: Any] = [:]
  if let current = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue() {
    inputSource["id"] = inputSourceProperty(current, kTISPropertyInputSourceID)
  }
  inputSource["enabled"] = keyboardLayouts()
    .filter { inputSourceFlag($0, kTISPropertyInputSourceIsEnabled) }
    .map { inputSourceProperty($0, kTISPropertyInputSourceID) }
  payload["inputSource"] = inputSource
  emit(payload)

case "apply":
  let json = requiredOption("settings")
  guard
    let data = json.data(using: .utf8),
    let requested = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
  else { die("invalid_settings_json") }
  var applied: [String: Any] = [:]
  for (name, value) in requested {
    let managed = setting(named: name)
    writeSetting(managed, value)
    applied[name] = readSetting(managed)
  }
  usleep(400_000)
  emit(["applied": applied])

case "input-sources":
  emit(["layouts": keyboardLayouts().map { source in
    [
      "enabled": inputSourceFlag(source, kTISPropertyInputSourceIsEnabled),
      "id": inputSourceProperty(source, kTISPropertyInputSourceID),
      "selectable": inputSourceFlag(source, kTISPropertyInputSourceIsSelectCapable),
    ]
  }])

case "select-input-source":
  let identifier = requiredOption("id")
  guard let source = layout(withIdentifier: identifier) else { die("unknown_input_source", identifier) }
  var enabledByUs = false
  if !inputSourceFlag(source, kTISPropertyInputSourceIsEnabled) {
    let status = TISEnableInputSource(source)
    if status != noErr { die("input_source_enable_failed", "\(identifier) (OSStatus \(status))") }
    enabledByUs = true
    usleep(400_000)
  }
  let status = TISSelectInputSource(source)
  if status != noErr { die("input_source_select_failed", "\(identifier) (OSStatus \(status))") }
  usleep(600_000)
  let current = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue()
  emit([
    "enabledByUs": enabledByUs,
    "selected": current.map { inputSourceProperty($0, kTISPropertyInputSourceID) } ?? "",
  ])

case "disable-input-source":
  let identifier = requiredOption("id")
  guard let source = layout(withIdentifier: identifier) else { die("unknown_input_source", identifier) }
  let status = TISDisableInputSource(source)
  emit(["disabled": status == noErr, "id": identifier])

case "screen-permission":
  emit(["granted": CGPreflightScreenCaptureAccess()])

case "contrast":
  guard let pid = pid_t(requiredOption("pid")) else { die("invalid_option", "--pid") }
  emit(analyseContrast(captureWindowImage(pid: pid)))

default:
  die("unknown_command", command)
}
