import AppKit

final class Launcher: NSObject, NSApplicationDelegate {
    private var process: Process?
    private var item: NSStatusItem!
    private let data = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/LocalWorkbench")
    func applicationDidFinishLaunching(_ notification: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "本地工作台")
        let menu = NSMenu()
        menu.addItem(withTitle: "打开工作台", action: #selector(openPage), keyEquivalent: "")
        menu.addItem(withTitle: "打开数据目录", action: #selector(openData), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "退出工作台", action: #selector(quit), keyEquivalent: "q")
        for entry in menu.items { entry.target = self }
        item.menu = menu
        do {
            try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
            let log = data.appendingPathComponent("desktop.log")
            if !FileManager.default.fileExists(atPath: log.path) { FileManager.default.createFile(atPath: log.path, contents: nil) }
            let handle = try FileHandle(forWritingTo: log)
            handle.seekToEndOfFile()
            let child = Process()
            child.executableURL = Bundle.main.resourceURL!.appendingPathComponent("backend/WorkbenchServer")
            child.environment = ProcessInfo.processInfo.environment.merging(["WORKBENCH_DATA_DIR": data.path]) { _, new in new }
            child.standardOutput = handle
            child.standardError = handle
            child.standardInput = FileHandle.nullDevice
            child.terminationHandler = { task in
                DispatchQueue.main.async {
                    if task.terminationStatus != 0 {
                        let alert = NSAlert()
                        alert.messageText = "工作台未能启动"
                        alert.informativeText = "请查看数据目录中的 desktop.log。"
                        alert.runModal()
                    }
                    NSApp.terminate(nil)
                }
            }
            process = child
            try child.run()
        } catch {
            let alert = NSAlert()
            alert.messageText = "工作台未能启动"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            NSApp.terminate(nil)
        }
    }
    @objc func openPage() {
        guard let bytes = try? Data(contentsOf: data.appendingPathComponent("desktop.json")),
              let state = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              let raw = state["url"] as? String,
              let url = URL(string: raw), url.host == "127.0.0.1",
              url.scheme == "http", (43140..<43150).contains(url.port ?? 0) else { return }
        NSWorkspace.shared.open(url)
    }
    @objc func openData() { NSWorkspace.shared.open(data) }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { openPage(); return false }
    func applicationWillTerminate(_ notification: Notification) { process?.terminationHandler = nil; if process?.isRunning == true { process?.terminate() } }
}
let app = NSApplication.shared
let delegate = Launcher()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
