import Foundation

var passed = 0
func check(_ condition: Bool, _ name: String) {
    guard condition else { fatalError(name) }; passed += 1
}
func rejected(_ name: String, _ operation: () throws -> Void) {
    do { try operation(); fatalError("Accepted invalid input: \(name)") } catch { passed += 1 }
}
let fixtures = URL(fileURLWithPath: CommandLine.arguments[1])
let digest = String(repeating: "a", count: 64)
func release(_ url: String, _ hash: String = String(repeating: "a", count: 64)) -> NativeRelease {
    NativeRelease(version: "1.2.0", url: url, sha256: hash, minimumSystemVersion: "15.0", notes: "")
}
check(NativeUpdater.newer("1.10.0", than: "1.9.0"), "numeric version order")
check(!NativeUpdater.newer("1.2.0", than: "1.2.0"), "same version")
check(!NativeUpdater.newer("1.1.0", than: "1.2.0"), "no downgrade")
let trusted = "https://github.com/Tyler9169/local-workbench/releases/download/v2.2.1/FrameRecorder.zip"
try NativeUpdater.validate(release(trusted)); passed += 1
rejected("host") { try NativeUpdater.validate(release("https://evil.example/app.zip")) }
rejected("repository") { try NativeUpdater.validate(release(trusted.replacingOccurrences(of: "Tyler9169", with: "someone"))) }
rejected("hash") { try NativeUpdater.validate(release(trusted, "invalid")) }
rejected("http") { try NativeUpdater.validate(release(trusted.replacingOccurrences(of: "https:", with: "http:"))) }
rejected("query") { try NativeUpdater.validate(release(trusted + "?redirect=1")) }
try NativeUpdater.validateZip(Data(contentsOf: fixtures.appendingPathComponent("good.zip")), appName: "Test.app"); passed += 1
for name in ["traversal", "symlink", "duplicate", "wrongroot", "localmismatch", "truncated"] {
    rejected(name) { try NativeUpdater.validateZip(Data(contentsOf: fixtures.appendingPathComponent(name + ".zip")), appName: "Test.app") }
}
if CommandLine.arguments.count > 2 {
    for (filename, appName) in [("PhotoPin-1.1.0-macOS-arm64.zip", "照片置顶.app"), ("FrameRecorder-1.2.0-macOS-arm64.zip", "框录.app")] {
        let file = URL(fileURLWithPath: CommandLine.arguments[2]).appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: file.path) {
            try NativeUpdater.validateZip(Data(contentsOf: file), appName: appName); passed += 1
        }
    }
}
print("Native updater validation: \(passed) assertions passed")
