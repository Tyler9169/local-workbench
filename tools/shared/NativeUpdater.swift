import AppKit
import CryptoKit

struct NativeRelease: Decodable {
    let version: String
    let url: String
    let sha256: String
    let minimumSystemVersion: String
    let notes: String
}
struct NativeFeed: Decodable { let schema: Int; let apps: [String: NativeRelease] }
struct UpdateFailure: LocalizedError {
    let text: String
    var errorDescription: String? { text }
}

// Shared by both apps. Preferences stay in their existing bundle-ID domains.
@MainActor final class NativeUpdater: NSObject {
    let bundle: Bundle
    let canInstall: () -> Bool
    var running = false
    var progress: NSAlert?
    var available: NativeRelease?
    var appID: String { bundle.bundleIdentifier! }
    var version: String { bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }
    var support: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(appID).appendingPathComponent("Updates") }
    init(bundle: Bundle = .main, canInstall: @escaping () -> Bool = { true }) { self.bundle = bundle; self.canInstall = canInstall }

    func didLaunch() {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "--native-update-token"), args.count > i + 1,
           UUID(uuidString: args[i + 1]) != nil {
            let ack = support.appendingPathComponent(args[i + 1] + ".ready")
            try? Data(version.utf8).write(to: ack, options: .atomic)
        }
        let result = support.appendingPathComponent("last-error.txt")
        if let message = try? String(contentsOf: result, encoding: .utf8) {
            try? FileManager.default.removeItem(at: result)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.show("更新未完成", message) }
        }
    }
    func show(_ title: String, _ detail: String) {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = detail
        NSApp.activate(ignoringOtherApps: true); alert.runModal()
    }
    func beginProgress(_ text: String) {
        let alert = NSAlert(); alert.messageText = text; alert.informativeText = "请稍候，现有设置和文件不会被删除。"
        alert.addButton(withTitle: "处理中…").isEnabled = false
        let spinner = NSProgressIndicator(frame: NSRect(x: 0, y: 0, width: 240, height: 18))
        spinner.style = .bar; spinner.isIndeterminate = true; spinner.startAnimation(nil)
        alert.accessoryView = spinner
        progress = alert; alert.window.center(); alert.window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func endProgress() { progress?.window.orderOut(nil); progress = nil }
    @objc func checkForUpdates() {
        guard !running else { progress?.window.makeKeyAndOrderFront(nil); return }
        running = true; beginProgress("正在检查更新…")
        Task {
            do {
                let url = URL(string: "https://raw.githubusercontent.com/Tyler9169/local-workbench/main/native-updates.json")!
                let bytes = try await Self.fetch(url, limit: 128 * 1024)
                let feed = try JSONDecoder().decode(NativeFeed.self, from: bytes)
                guard feed.schema == 1, let release = feed.apps[appID] else { throw UpdateFailure(text: "更新信息不完整，请稍后重试。") }
                try Self.validate(release)
                endProgress()
                guard Self.newer(release.version, than: version) else {
                    running = false; show("已是最新版本", "\(bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "应用") \(version)"); return
                }
                let os = ProcessInfo.processInfo.operatingSystemVersion
                let system = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
                guard !Self.newer(release.minimumSystemVersion, than: system) else { throw UpdateFailure(text: "新版需要 macOS \(release.minimumSystemVersion) 或更新版本；当前版本可继续使用。") }
                available = release
                let alert = NSAlert(); alert.messageText = "发现新版本 \(release.version)"
                alert.informativeText = "当前版本 \(version)\n\n\(release.notes)\n\n更新会保留设置，并自动重新打开。macOS 可能要求重新授权。"
                alert.addButton(withTitle: "一键更新"); alert.addButton(withTitle: "稍后")
                guard alert.runModal() == .alertFirstButtonReturn else { running = false; return }
                guard canInstall() else { throw UpdateFailure(text: "请先停止录制或等待当前操作完成，再安装更新。") }
                beginProgress("正在下载并验证更新…")
                let bundlePath = bundle.bundleURL.path, supportPath = support.path
                let plan = try await Task.detached { try await Self.prepare(release, bundlePath: bundlePath, supportPath: supportPath) }.value
                guard canInstall() else { try? FileManager.default.removeItem(at: plan.stage); throw UpdateFailure(text: "当前操作尚未结束，请停止录制后重试。") }
                UserDefaults.standard.synchronize()
                if let domain = UserDefaults.standard.persistentDomain(forName: appID) {
                    let data = try PropertyListSerialization.data(fromPropertyList: domain, format: .xml, options: 0)
                    try data.write(to: support.appendingPathComponent("settings-\(plan.token).plist"), options: .atomic)
                }
                let helper = Process(); helper.executableURL = URL(fileURLWithPath: "/bin/bash")
                helper.arguments = [plan.helper.path, String(ProcessInfo.processInfo.processIdentifier), bundle.bundleURL.resolvingSymlinksInPath().path, plan.stage.path, support.path, plan.token]
                let log = support.appendingPathComponent("install.log")
                FileManager.default.createFile(atPath: log.path, contents: nil)
                let handle = try FileHandle(forWritingTo: log); helper.standardOutput = handle; helper.standardError = handle
                try helper.run(); endProgress(); NSApp.terminate(nil)
            } catch { endProgress(); running = false; show("更新未完成", error.localizedDescription) }
        }
    }
    nonisolated static func newer(_ candidate: String, than current: String) -> Bool {
        candidate.compare(current, options: .numeric) == .orderedDescending
    }
    nonisolated static func validate(_ r: NativeRelease) throws {
        guard r.version.range(of: #"^\d+\.\d+(\.\d+)?$"#, options: .regularExpression) != nil,
              r.minimumSystemVersion.range(of: #"^\d+(\.\d+){0,2}$"#, options: .regularExpression) != nil,
              r.sha256.range(of: #"^[a-f0-9]{64}$"#, options: .regularExpression) != nil,
              let u = URL(string: r.url), u.scheme == "https", u.host == "github.com", u.query == nil, u.fragment == nil,
              u.path.hasPrefix("/Tyler9169/local-workbench/releases/download/"), u.path.hasSuffix(".zip"), !u.path.contains("..")
        else { throw UpdateFailure(text: "更新来源或校验信息无效。") }
    }
    nonisolated static func fetch(_ url: URL, limit: Int) async throws -> Data {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30; config.timeoutIntervalForResource = 180
        let session = URLSession(configuration: config); defer { session.invalidateAndCancel() }
        var last: Error = UpdateFailure(text: "下载失败")
        for _ in 0..<3 {
            do {
                let (file, response) = try await session.download(for: URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))
                defer { try? FileManager.default.removeItem(at: file) }
                guard (response as? HTTPURLResponse)?.statusCode == 200,
                      let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= limit else { throw UpdateFailure(text: "更新服务器暂时不可用，或文件大小异常。") }
                return try Data(contentsOf: file)
            } catch { last = error }
        }
        throw last
    }
    nonisolated static func command(_ executable: String, _ args: [String]) throws -> String {
        let task = Process(); task.executableURL = URL(fileURLWithPath: executable); task.arguments = args
        let pipe = Pipe(); task.standardOutput = pipe; task.standardError = pipe
        try task.run(); let output = pipe.fileHandleForReading.readDataToEndOfFile(); task.waitUntilExit()
        guard task.terminationStatus == 0 else { throw UpdateFailure(text: "验证或准备更新失败：\(String(data: output, encoding: .utf8) ?? executable)") }
        return String(data: output, encoding: .utf8) ?? ""
    }
    // Inspect central-directory entries before extraction, rejecting links and escaped paths.
    nonisolated static func validateZip(_ data: Data, appName: String) throws {
        func invalid() -> UpdateFailure { UpdateFailure(text: "更新压缩包结构无效。") }
        func number(_ offset: Int, _ count: Int) throws -> Int {
            guard offset >= 0, offset + count <= data.count else { throw invalid() }
            return (0..<count).reduce(0) { $0 | Int(data[offset + $1]) << ($1 * 8) }
        }
        guard data.count >= 22 else { throw invalid() }
        var end: Int?
        for i in stride(from: data.count - 22, through: max(0, data.count - 65557), by: -1) {
            if try number(i, 4) == 0x06054b50, i + 22 + (try number(i + 20, 2)) == data.count { end = i; break }
        }
        guard let e = end, try number(e + 4, 2) == 0, try number(e + 6, 2) == 0 else { throw invalid() }
        let count = try number(e + 10, 2); var offset = try number(e + 16, 4)
        guard count > 0, count < 5000, try number(e + 8, 2) == count,
              offset + (try number(e + 12, 4)) == e else { throw invalid() }
        var seen = Set<String>(); var total = 0
        for _ in 0..<count {
            guard try number(offset, 4) == 0x02014b50 else { throw invalid() }
            let length = try number(offset + 28, 2), extra = try number(offset + 30, 2), comment = try number(offset + 32, 2)
            guard offset + 46 + length <= e, let name = String(data: data[(offset + 46)..<(offset + 46 + length)], encoding: .utf8),
                  name.hasPrefix(appName + "/"), !name.contains("\\"), !name.contains("\0"),
                  !name.split(separator: "/", omittingEmptySubsequences: false).contains(".."),
                  !name.split(separator: "/").contains("."), seen.insert(name).inserted,
                  (try number(offset + 38, 4) >> 16) & 0xF000 != 0xA000,
                  try number(offset + 8, 2) & 1 == 0 else { throw invalid() }
            let local = try number(offset + 42, 4)
            let localLength = try number(local + 26, 2)
            guard try number(local, 4) == 0x04034b50, local + 30 + localLength <= data.count,
                  String(data: data[(local + 30)..<(local + 30 + localLength)], encoding: .utf8) == name,
                  try number(offset + 34, 2) == 0 else { throw invalid() }
            total += try number(offset + 24, 4)
            guard total <= 100 * 1024 * 1024 else { throw invalid() }
            offset += 46 + length + extra + comment
        }
        guard offset == e else { throw invalid() }
    }
    struct Plan { let stage: URL; let helper: URL; let token: String }
    nonisolated static func prepare(_ release: NativeRelease, bundlePath: String, supportPath: String) async throws -> Plan {
        try validate(release)
        let fm = FileManager.default, target = URL(fileURLWithPath: bundlePath).resolvingSymlinksInPath()
        guard !target.path.hasPrefix("/Volumes/"), !target.path.contains("/AppTranslocation/"),
              fm.isWritableFile(atPath: target.deletingLastPathComponent().path) else { throw UpdateFailure(text: "请先将应用移到可写的应用程序文件夹，再检查更新。") }
        let token = UUID().uuidString, support = URL(fileURLWithPath: supportPath)
        try fm.createDirectory(at: support, withIntermediateDirectories: true)
        let stage = target.deletingLastPathComponent().appendingPathComponent(".native-update-" + token)
        try fm.createDirectory(at: stage, withIntermediateDirectories: false)
        do {
            let data = try await fetch(URL(string: release.url)!, limit: 30 * 1024 * 1024)
            guard SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == release.sha256 else { throw UpdateFailure(text: "安装包校验失败，原版本未被修改。") }
            // Package name comes from bundle identity, not the local app filename (users may rename it).
            let old = Bundle(url: target)!, name = (old.object(forInfoDictionaryKey: "CFBundleName") as! String) + ".app"
            try validateZip(data, appName: name)
            let zip = stage.appendingPathComponent("update.zip"); try data.write(to: zip)
            _ = try command("/usr/bin/ditto", ["-x", "-k", zip.path, stage.path]); try fm.removeItem(at: zip)
            let app = stage.appendingPathComponent(name)
            guard let new = Bundle(url: app), new.bundleIdentifier == old.bundleIdentifier,
                  new.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == release.version,
                  new.object(forInfoDictionaryKey: "CFBundleExecutable") as? String == old.object(forInfoDictionaryKey: "CFBundleExecutable") as? String else { throw UpdateFailure(text: "安装包与当前应用不匹配。") }
            _ = try command("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
            // Signed distributions must retain their existing designated requirement. Ad-hoc
            // builds have version-specific requirements, so cannot offer permission continuity.
            let signature = try command("/usr/bin/codesign", ["-d", "-r-", target.path])
            if let dr = signature.components(separatedBy: "designated => ").last, !dr.contains("cdhash") {
                _ = try command("/usr/bin/codesign", ["--verify", "-R=" + dr.trimmingCharacters(in: .whitespacesAndNewlines), app.path])
            }
            let helper = support.appendingPathComponent("install-" + token + ".sh")
            guard let bundledHelper = old.url(forResource: "install-update", withExtension: "sh") else { throw UpdateFailure(text: "缺少更新组件，请重新下载安装包。") }
            try fm.copyItem(at: bundledHelper, to: helper)
            // Helper receives a fixed staged name independent of the user's app filename.
            try fm.moveItem(at: app, to: stage.appendingPathComponent("Application.app"))
            return Plan(stage: stage, helper: helper, token: token)
        } catch { try? fm.removeItem(at: stage); throw error }
    }
}
