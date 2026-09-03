import ApplicationServices
import CoreGraphics
import Foundation

/// Reports what macOS privacy (TCC) permissions the CURRENT process actually
/// has, as JSON, without ever prompting.
///
/// Purpose (Plan 03-17 Task 4): it is genuinely unknown whether a
/// GitHub-hosted `macos-15` runner can be granted Accessibility, Screen
/// Recording, or a write to the protected `com.apple.universalaccess`
/// preference domain. Rather than designing around a guess, this probe makes
/// one real CI run produce a definitive answer either way.
///
/// Never prompts: `kAXTrustedCheckOptionPrompt: false` and
/// `CGPreflightScreenCaptureAccess()` (preflight, not request). A prompt on a
/// non-interactive runner would hang until the job timed out and would tell
/// us nothing.
///
/// The `com.apple.universalaccess` check writes a probe-private key
/// (`keeplingTccProbe`), reads it back, and then removes it. It never touches
/// a real accessibility setting, so it is safe to run on a personal machine.

func isAccessibilityTrusted() -> Bool {
  let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
  return AXIsProcessTrustedWithOptions(options)
}

func universalAccessWritePersists() -> [String: Any] {
  let domain = "com.apple.universalaccess" as CFString
  let key = "keeplingTccProbe" as CFString
  let token = "keepling-\(UUID().uuidString)"

  CFPreferencesSetValue(key, token as CFString, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
  let synchronized = CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
  let readBack = CFPreferencesCopyValue(key, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? String

  // Always clean up, whether or not the write appeared to land.
  CFPreferencesSetValue(key, nil, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
  _ = CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)

  return [
    "persisted": readBack == token,
    "read_back_matched_token": readBack == token,
    "synchronize_returned_true": synchronized,
  ]
}

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

let report: [String: Any] = [
  "accessibility_trusted": isAccessibilityTrusted(),
  "process_ancestry": processAncestry(),
  "screen_recording_preflight": CGPreflightScreenCaptureAccess(),
  "universal_access_write": universalAccessWritePersists(),
]

let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
FileHandle.standardOutput.write(data)
FileHandle.standardOutput.write("\n".data(using: .utf8)!)
