import AppKit
import UniformTypeIdentifiers

final class HoverContentView: NSView {
    weak var controls: NSView?
    private var hoverArea: NSTrackingArea?
    private var hideWork: DispatchWorkItem?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect, .enabledDuringMouseDrag], owner: self)
        addTrackingArea(area)
        hoverArea = area
        refreshHover()
    }
    func refreshHover() {
        guard let window else { return }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        setHovered(bounds.contains(point))
    }
    private func setHovered(_ inside: Bool) {
        hideWork?.cancel()
        if inside {
            controls?.isHidden = false
        } else {
            let work = DispatchWorkItem { [weak self] in self?.controls?.isHidden = true }
            hideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
        }
    }
    override func mouseEntered(with event: NSEvent) { setHovered(true) }
    override func mouseExited(with event: NSEvent) { setHovered(false) }
    deinit { hideWork?.cancel() }
}

final class PhotoView: NSView {
    var image: NSImage? { didSet { resetZoom() } }
    var locked = false
    private(set) var zoom: CGFloat = 1
    private var offset = NSPoint.zero
    private var dragPoint: NSPoint?
    var onZoom: ((CGFloat) -> Void)?
    var onFile: ((URL) -> Void)?
    var onChoose: (() -> Void)?
    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { fatalError() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    private var displayedSize: NSSize {
        guard let image, image.size.width > 0, image.size.height > 0 else { return .zero }
        let fit = min(bounds.width / image.size.width, bounds.height / image.size.height)
        return NSSize(width: image.size.width * fit * zoom, height: image.size.height * fit * zoom)
    }
    private func clampOffset() {
        let size = displayedSize
        let xLimit = max(0, (size.width - bounds.width) / 2)
        let yLimit = max(0, (size.height - bounds.height) / 2)
        offset.x = min(xLimit, max(-xLimit, offset.x))
        offset.y = min(yLimit, max(-yLimit, offset.y))
    }
    func changeZoom(by factor: CGFloat, anchor: NSPoint? = nil) {
        guard image != nil, factor.isFinite, factor > 0 else { return }
        let next = min(10, max(0.1, zoom * factor))
        let ratio = next / zoom
        let point = anchor ?? NSPoint(x: bounds.midX, y: bounds.midY)
        offset.x = (point.x - bounds.midX) * (1 - ratio) + offset.x * ratio
        offset.y = (point.y - bounds.midY) * (1 - ratio) + offset.y * ratio
        zoom = next
        updateZoom()
    }
    func resetZoom() {
        zoom = 1
        offset = .zero
        updateZoom()
    }
    private func updateZoom() {
        clampOffset()
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
        onZoom?(zoom)
    }
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        clampOffset()
        needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        bounds.clip()
        NSColor(calibratedWhite: 0.10, alpha: 1).setFill()
        bounds.fill()
        if let image = image, image.size.width > 0, image.size.height > 0 {
            let size = displayedSize
            let rect = NSRect(x: (bounds.width-size.width)/2 + offset.x, y: (bounds.height-size.height)/2 + offset.y, width: size.width, height: size.height)
            NSGraphicsContext.current?.imageInterpolation = .high
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        } else {
            let message = "拖入一张照片\n或点击上方「选择照片」\n\n拖动照片即可移动窗口"
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            style.lineSpacing = 9
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 16), .foregroundColor: NSColor.lightGray, .paragraphStyle: style]
            let rect = NSRect(x: 20, y: bounds.midY-65, width: max(0, bounds.width-40), height: 130)
            (message as NSString).draw(in: rect, withAttributes: attributes)
        }
    }
    override func mouseDown(with event: NSEvent) {
        dragPoint = nil
        if event.clickCount == 2 {
            if image == nil { onChoose?() } else { resetZoom() }
            return
        }
        if image != nil && zoom > 1 && !event.modifierFlags.contains(.option) {
            dragPoint = convert(event.locationInWindow, from: nil)
            return
        }
        if !locked { window?.performDrag(with: event) }
    }
    override func mouseDragged(with event: NSEvent) {
        guard let previous = dragPoint else { return }
        let point = convert(event.locationInWindow, from: nil)
        offset.x += point.x - previous.x
        offset.y += point.y - previous.y
        dragPoint = point
        clampOffset()
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) { dragPoint = nil }
    override func scrollWheel(with event: NSEvent) {
        let sensitivity: CGFloat = event.hasPreciseScrollingDeltas ? 0.008 : 0.08
        let delta = min(2, max(-2, event.scrollingDeltaY * sensitivity))
        changeZoom(by: exp(delta), anchor: convert(event.locationInWindow, from: nil))
    }
    override func magnify(with event: NSEvent) {
        changeZoom(by: max(0.01, 1 + event.magnification), anchor: convert(event.locationInWindow, from: nil))
    }
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: (!locked || (image != nil && zoom > 1)) ? .openHand : .arrow)
    }
    private func droppedURL(_ sender: NSDraggingInfo) -> URL? {
        (sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL])?.first
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        droppedURL(sender) == nil ? [] : .copy
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let url = droppedURL(sender) else { return false }
        onFile?(url)
        return true
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!
    let photo = PhotoView(frame: .zero)
    let lockButton = NSButton(title: "锁定位置", target: nil, action: nil)
    let status = NSTextField(labelWithString: "始终置顶 · 可拖动")
    let zoomLabel = NSTextField(labelWithString: "100%")
    let root = HoverContentView()
    var lockMenu: NSMenuItem!
    var locked = false
    let defaults = UserDefaults.standard

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        window = NSWindow(contentRect: NSRect(x: 160, y: 180, width: 460, height: 420), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "照片置顶"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(type)?.isHidden = true
        }
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 340, height: 200)
        window.delegate = self
        window.setFrameAutosaveName("PhotoPinWindow")
        window.contentView = root
        let controls = NSVisualEffectView()
        controls.material = .hudWindow
        controls.blendingMode = .withinWindow
        controls.state = .active
        controls.wantsLayer = true
        controls.layer?.cornerRadius = 10
        controls.isHidden = true
        root.controls = controls
        let choose = NSButton(title: "选择照片…", target: self, action: #selector(choosePhoto))
        choose.bezelStyle = .rounded
        choose.toolTip = "打开照片（⌘O），也可直接拖入照片"
        lockButton.target = self
        lockButton.action = #selector(toggleLock)
        lockButton.bezelStyle = .rounded
        lockButton.toolTip = "锁定或解锁窗口位置和大小（⌘L）"
        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        let close = NSButton(title: "关闭", target: self, action: #selector(closeApp))
        close.bezelStyle = .rounded
        close.toolTip = "关闭照片窗口并退出（⌘Q）"
        let bar = NSStackView(views: [choose, lockButton, close])
        bar.orientation = .horizontal
        bar.spacing = 8
        let minus = NSButton(title: "−", target: self, action: #selector(zoomOut))
        let plus = NSButton(title: "＋", target: self, action: #selector(zoomIn))
        let fit = NSButton(title: "适应窗口", target: self, action: #selector(fitPhoto))
        minus.toolTip = "缩小照片（⌘−）"
        plus.toolTip = "放大照片（⌘＋）；也可滚轮缩放或触控板捏合"
        fit.toolTip = "恢复完整显示（⌘0 或双击照片）；100% 表示适应窗口"
        for button in [minus, plus, fit] { button.bezelStyle = .rounded }
        zoomLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        zoomLabel.alignment = .center
        zoomLabel.widthAnchor.constraint(equalToConstant: 52).isActive = true
        let zoomBar = NSStackView(views: [minus, zoomLabel, plus, fit])
        zoomBar.orientation = .horizontal
        zoomBar.spacing = 6
        photo.onZoom = { [weak self] zoom in
            self?.zoomLabel.stringValue = "\(Int((zoom * 100).rounded()))%"
            self?.updateStatus()
        }
        for view in [photo, controls] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        for view in [bar, zoomBar, status] {
            view.translatesAutoresizingMaskIntoConstraints = false
            controls.addSubview(view)
        }
        NSLayoutConstraint.activate([
            controls.topAnchor.constraint(equalTo: root.topAnchor, constant: 26),
            controls.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 8),
            controls.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -8),
            controls.bottomAnchor.constraint(equalTo: status.bottomAnchor, constant: 9),
            bar.topAnchor.constraint(equalTo: controls.topAnchor, constant: 9),
            bar.leadingAnchor.constraint(equalTo: controls.leadingAnchor, constant: 8),
            zoomBar.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 5),
            zoomBar.leadingAnchor.constraint(equalTo: controls.leadingAnchor, constant: 8),
            status.topAnchor.constraint(equalTo: zoomBar.bottomAnchor, constant: 5),
            status.leadingAnchor.constraint(equalTo: controls.leadingAnchor, constant: 10),
            photo.topAnchor.constraint(equalTo: root.topAnchor),
            photo.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            photo.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            photo.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
        photo.onFile = { [weak self] url in self?.loadPhoto(url) }
        photo.onChoose = { [weak self] in self?.choosePhoto() }
        if let path = defaults.string(forKey: "lastPhoto"), let image = NSImage(contentsOfFile: path) {
            photo.image = image
            window.title = URL(fileURLWithPath: path).lastPathComponent + " · 照片置顶"
        }
        setLocked(defaults.bool(forKey: "locked"))
        // Recover the window if a previously used monitor has been disconnected.
        if !NSScreen.screens.contains(where: { $0.visibleFrame.intersection(window.frame).width >= 100 && $0.visibleFrame.intersection(window.frame).height >= 80 }) {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        root.refreshHover()
    }

    func buildMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "退出照片置顶", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        menu.addItem(appItem)
        let fileItem = NSMenuItem(title: "照片", action: nil, keyEquivalent: "")
        let fileMenu = NSMenu(title: "照片")
        let open = fileMenu.addItem(withTitle: "选择照片…", action: #selector(choosePhoto), keyEquivalent: "o")
        open.target = self
        lockMenu = fileMenu.addItem(withTitle: "锁定位置", action: #selector(toggleLock), keyEquivalent: "l")
        lockMenu.target = self
        fileMenu.addItem(.separator())
        for (title, action, key) in [("放大照片", #selector(zoomIn), "="), ("缩小照片", #selector(zoomOut), "-"), ("适应窗口", #selector(fitPhoto), "0")] {
            let item = fileMenu.addItem(withTitle: title, action: action, keyEquivalent: key)
            item.target = self
        }
        let plusShortcut = fileMenu.addItem(withTitle: "放大照片", action: #selector(zoomIn), keyEquivalent: "+")
        plusShortcut.target = self
        plusShortcut.isHidden = true
        plusShortcut.allowsKeyEquivalentWhenHidden = true
        fileItem.submenu = fileMenu
        menu.addItem(fileItem)
        NSApp.mainMenu = menu
    }

    @objc func choosePhoto() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "显示照片"
        panel.beginSheetModal(for: window) { [weak self] response in
            if response == .OK, let url = panel.url { self?.loadPhoto(url) }
        }
    }

    func loadPhoto(_ url: URL) {
        guard let image = NSImage(contentsOf: url), image.size.width > 0, image.size.height > 0 else {
            let alert = NSAlert()
            alert.messageText = "无法打开这张照片"
            alert.informativeText = "请选择有效的图片文件，例如 JPG、PNG、HEIC 或 TIFF。"
            alert.beginSheetModal(for: window)
            return
        }
        photo.image = image
        defaults.set(url.path, forKey: "lastPhoto")
        window.title = url.lastPathComponent + " · 照片置顶"
    }

    @objc func closeApp() { NSApp.terminate(nil) }
    @objc func zoomIn() { photo.changeZoom(by: 1.25) }
    @objc func zoomOut() { photo.changeZoom(by: 0.8) }
    @objc func fitPhoto() { photo.resetZoom() }
    @objc func toggleLock() { setLocked(!locked) }
    func updateStatus() {
        if photo.zoom > 1 {
            status.stringValue = locked ? "窗口已锁定 · 拖动照片查看细节" : "拖动照片查看细节 · 拖动标题栏移动窗口"
        } else {
            status.stringValue = locked ? "窗口已锁定 · 滚轮可缩放照片" : "拖动照片移动窗口 · 滚轮缩放照片"
        }
    }
    func setLocked(_ value: Bool) {
        locked = value
        photo.locked = value
        window.isMovable = !value
        if value { window.styleMask.remove(.resizable) }
        else { window.styleMask.insert(.resizable) }
        lockButton.title = value ? "解锁位置" : "锁定位置"
        updateStatus()
        lockMenu.state = value ? .on : .off
        defaults.set(value, forKey: "locked")
        window.invalidateCursorRects(for: photo)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.setActivationPolicy(.regular)
application.delegate = delegate
application.run()
