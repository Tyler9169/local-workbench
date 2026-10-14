import AppKit
@preconcurrency import ScreenCaptureKit
import AVFoundation
import Carbon

let gold=NSColor(calibratedRed:1,green:0.83,blue:0.18,alpha:1)
let dark=NSColor(calibratedRed:0.10,green:0.12,blue:0.16,alpha:1)

final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override func accessibilityPerformRaise() -> Bool {makeKeyAndOrderFront(nil);return true}
    override var canBecomeMain: Bool { true }
}

final class RegionView: NSView {
    weak var owner: RecorderApp?
    let captureScreen: NSScreen
    var rect=CGRect.zero
    var recording=false
    var mouseStart=CGPoint.zero
    var original=CGRect.zero
    var mode = -2 // -2 new, -1 move, 0..8 resize
    init(screen: NSScreen, owner: RecorderApp) {
        self.captureScreen=screen;self.owner=owner
        super.init(frame:CGRect(origin:.zero,size:screen.frame.size))
    }
    required init?(coder:NSCoder){fatalError()}
    override var acceptsFirstResponder: Bool {true}
    func handles() -> [(Int,CGPoint)] {
        [0,1,2,3,5,6,7,8].map { i in
            let xs=[rect.minX,rect.midX,rect.maxX], ys=[rect.minY,rect.midY,rect.maxY]
            return (i,CGPoint(x:xs[i%3],y:ys[i/3]))
        }
    }
    override func draw(_ dirtyRect:NSRect){
        if !recording {
            let shade=NSBezierPath(rect:bounds)
            if !rect.isEmpty {shade.appendRect(rect)}
            shade.windingRule = .evenOdd
            NSColor.black.withAlphaComponent(0.30).setFill();shade.fill()
        }
        if !rect.isEmpty {
            (recording ? NSColor.systemRed:gold).setStroke()
            let border=NSBezierPath(rect:rect);border.lineWidth=2;border.stroke()
            if !recording {
                for (_,p) in handles(){gold.setFill();NSBezierPath(roundedRect:CGRect(x:p.x-5,y:p.y-5,width:10,height:10),xRadius:2,yRadius:2).fill()}
            }
        } else {
            let text="拖出一个区域 · 拖动框内移动 · 拖动八个控制点缩放 · S 截图 · 空格录制 · Esc 取消" as NSString
            let style:[NSAttributedString.Key:Any]=[.font:NSFont.systemFont(ofSize:18,weight:.medium),.foregroundColor:NSColor.white]
            let size=text.size(withAttributes:style)
            text.draw(at:CGPoint(x:(bounds.width-size.width)/2,y:bounds.height-100),withAttributes:style)
        }
    }
    override func resetCursorRects(){
        addCursorRect(bounds,cursor:.crosshair)
        if !rect.isEmpty {addCursorRect(rect.insetBy(dx:12,dy:12),cursor:.openHand)}
    }
    override func mouseDown(with event:NSEvent){
        guard owner?.isBusy == false else{return}
        owner?.activateRegion(self)
        mouseStart=convert(event.locationInWindow,from:nil);original=rect
        mode = handles().first(where: {abs($0.1.x-mouseStart.x)<12 && abs($0.1.y-mouseStart.y)<12 && !rect.isEmpty})?.0 ?? (rect.contains(mouseStart) ? -1 : -2)
        if mode == -2 {rect = .zero}
    }
    override func mouseDragged(with event:NSEvent){
        guard owner?.isBusy == false else{return}
        let p=convert(event.locationInWindow,from:nil)
        if mode == -2 {rect=RegionGeometry.normalized(mouseStart,p,bounds:bounds)}
        else if mode == -1 {rect=RegionGeometry.moved(original,dx:p.x-mouseStart.x,dy:p.y-mouseStart.y,bounds:bounds)}
        else {rect=RegionGeometry.resized(original,handle:mode,point:p,bounds:bounds)}
        needsDisplay=true;owner?.regionChanged(self)
    }
    override func mouseUp(with event:NSEvent){
        if rect.width<40 || rect.height<40 {rect = .zero}
        needsDisplay=true;window?.invalidateCursorRects(for:self);owner?.regionChanged(self)
    }
    override func keyDown(with event:NSEvent){
        if event.keyCode==53 {owner?.cancelSelection()}
        else if event.charactersIgnoringModifiers?.lowercased()=="s" {owner?.takeScreenshot()}
        else if event.charactersIgnoringModifiers==" " {owner?.toggleRecording()}
        else {super.keyDown(with:event)}
    }
}

@MainActor final class RecorderApp: NSObject, NSApplicationDelegate, NSWindowDelegate, SCRecordingOutputDelegate, SCStreamDelegate {
    var statusItem:NSStatusItem!
    var home:NSWindow!
    var toolbar:NSPanel!
    var overlays:[OverlayWindow]=[]
    weak var selected:RegionView?
    var statusLabel=NSTextField(labelWithString:"")
    var dimensions=NSTextField(labelWithString:"请拖出录制区域")
    var clockLabel=NSTextField(labelWithString:"未录制")
    var fpsBox=NSPopUpButton()
    var cursorBox=NSButton(checkboxWithTitle:"包含鼠标指针",target:nil,action:nil)
    var systemAudioBox=NSButton(checkboxWithTitle:"系统声音",target:nil,action:nil)
    var microphoneBox=NSButton(checkboxWithTitle:"麦克风",target:nil,action:nil)
    var captureButton:NSButton!
    var recordButton:NSButton!
    var reselectButton:NSButton!
    var stopMenu:NSMenuItem!
    var isBusy=false
    var isRecording=false
    var finishing=false
    var stream:SCStream?
    var output:SCRecordingOutput?
    var outputURL:URL?
    var started=Date()
    var timer:Timer?
    var latestURL:URL?
    var pendingQuit=false
    var hotKeys:[EventHotKeyRef?]=[]
    var hotKeyResults:[String:Int32]=[:]
    let saveDirectory=FileManager.default.urls(for:.moviesDirectory,in:.userDomainMask)[0].appendingPathComponent("框录")
    let stateDirectory=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("框录")

    func applicationDidFinishLaunching(_ notification:Notification){
        do {try FileManager.default.createDirectory(at:saveDirectory,withIntermediateDirectories:true);try FileManager.default.createDirectory(at:stateDirectory,withIntermediateDirectories:true)}catch{}
        setupMenu();setupHome();setupToolbar();setupHotkeys()
        NotificationCenter.default.addObserver(self,selector:#selector(displaysChanged),name:NSApplication.didChangeScreenParametersNotification,object:nil)
        showHome();writeState("idle")
    }
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool)->Bool {showHome();return true}
    func windowShouldClose(_ sender:NSWindow)->Bool {sender.orderOut(nil);return false}
    func text(_ string:String,size:CGFloat=14,color:NSColor = .labelColor)->NSTextField {
        let t=NSTextField(wrappingLabelWithString:string);t.font = .systemFont(ofSize:size);t.textColor=color;return t
    }
    func button(_ title:String,_ action:Selector)->NSButton {
        let b=NSButton(title:title,target:self,action:action);b.bezelStyle = .rounded;b.controlSize = .large;return b
    }
    func setupMenu(){
        statusItem=NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength)
        statusItem.button?.image=NSImage(systemSymbolName:"viewfinder",accessibilityDescription:"框录")
        let menu=NSMenu()
        func item(_ name:String,_ selector:Selector){let m=NSMenuItem(title:name,action:selector,keyEquivalent:"");m.target=self;menu.addItem(m)}
        item("框选区域    ⌃⌥A",#selector(selectArea));item("开始 / 停止录制    ⌃⌥R",#selector(toggleRecording))
        stopMenu=menu.items.last!
        menu.addItem(.separator());item("显示控制面板",#selector(showHome));item("打开输出文件夹",#selector(openFolder));item("屏幕录制权限",#selector(requestPermission));menu.addItem(.separator());item("退出框录",#selector(quit))
        statusItem.menu=menu
    }
    func setupHome(){
        home=NSWindow(contentRect:NSRect(x:0,y:0,width:540,height:550),styleMask:[.titled,.closable,.miniaturizable],backing:.buffered,defer:false)
        home.title="框录";home.delegate=self;home.appearance=NSAppearance(named:.darkAqua);home.backgroundColor=dark;home.isReleasedWhenClosed=false
        let title=text("框住这一块，就开始。",size:28,color:.white)
        let sub=text("区域截图与录屏 · 原生分辨率 · 本机保存",size:13,color:.secondaryLabelColor)
        let choose=button("＋ 框选屏幕区域",#selector(selectArea));choose.bezelColor=gold;choose.contentTintColor = .black
        let shortcut=text("随时调用：Control + Option + A\n开始 / 停止：Control + Option + R",size:13,color:.secondaryLabelColor)
        fpsBox.addItems(withTitles:["15 fps","24 fps","30 fps","60 fps"]);fpsBox.selectItem(at:2)
        cursorBox.state = .on
        let settings=NSStackView(views:[text("录制帧率",size:13),fpsBox,cursorBox]);settings.spacing=14
        systemAudioBox.state=UserDefaults.standard.bool(forKey:"systemAudio") ? .on:.off
        microphoneBox.state=UserDefaults.standard.bool(forKey:"microphone") ? .on:.off
        for box in [systemAudioBox,microphoneBox] {box.target=self;box.action=#selector(audioChanged(_:))}
        let audioSettings=NSStackView(views:[text("录制声音",size:13),systemAudioBox,microphoneBox]);audioSettings.spacing=18
        let limits=text("选好后可拖动整个区域，或拖动八个控制点缩放。录制期间选区锁定，红框与计时提示始终可见。\n两个声音开关可独立选择；都关闭即无声录制。麦克风使用系统默认输入设备。每次选择一块显示器内的区域。",size:13,color:.secondaryLabelColor)
        statusLabel=text("",size:12,color:gold)
        let actions=NSStackView(views:[button("授权屏幕录制",#selector(requestPermission)),button("输出文件夹",#selector(openFolder))]);actions.spacing=12
        let stack=NSStackView(views:[title,sub,choose,shortcut,settings,audioSettings,limits,statusLabel,actions]);stack.orientation = .vertical;stack.alignment = .leading;stack.spacing=18;stack.translatesAutoresizingMaskIntoConstraints=false
        home.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:home.contentView!.leadingAnchor,constant:30),stack.trailingAnchor.constraint(equalTo:home.contentView!.trailingAnchor,constant:-30),stack.topAnchor.constraint(equalTo:home.contentView!.topAnchor,constant:25)])
        home.center()
    }
    func setupToolbar(){
        toolbar=NSPanel(contentRect:NSRect(x:0,y:0,width:610,height:98),styleMask:[.titled,.utilityWindow],backing:.buffered,defer:false)
        toolbar.title="框录 · 拖动选区 / 八点缩放";toolbar.level=NSWindow.Level(rawValue:NSWindow.Level.screenSaver.rawValue+1)
        toolbar.isFloatingPanel=true;toolbar.hidesOnDeactivate=false;toolbar.appearance=NSAppearance(named:.darkAqua);toolbar.backgroundColor=dark
        toolbar.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary];toolbar.isMovableByWindowBackground=true
        dimensions=text("请框选区域",size:13,color:.white);clockLabel=text("未录制",size:13,color:gold)
        let top=NSStackView(views:[dimensions,clockLabel]);top.distribution = .fill;top.spacing=20
        captureButton=button("截图 PNG",#selector(takeScreenshot));recordButton=button("● 开始录制",#selector(toggleRecording));recordButton.bezelColor=gold;recordButton.contentTintColor = .black
        reselectButton=button("重新框选",#selector(selectArea))
        let cancel=button("收起",#selector(cancelSelection))
        let actions=NSStackView(views:[captureButton,recordButton,reselectButton,cancel]);actions.spacing=8
        let stack=NSStackView(views:[top,actions]);stack.orientation = .vertical;stack.alignment = .leading;stack.spacing=10;stack.translatesAutoresizingMaskIntoConstraints=false
        toolbar.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:toolbar.contentView!.leadingAnchor,constant:14),stack.topAnchor.constraint(equalTo:toolbar.contentView!.topAnchor,constant:10),stack.trailingAnchor.constraint(lessThanOrEqualTo:toolbar.contentView!.trailingAnchor,constant:-14)])
    }
    @objc func showHome(){
        updatePermissionLabel();NSApp.activate(ignoringOtherApps:true);home.makeKeyAndOrderFront(nil)
    }
    func updatePermissionLabel(){statusLabel.stringValue=CGPreflightScreenCaptureAccess() ? "已获得屏幕录制权限 · 文件保存到 影片 / 框录" : "尚未获得屏幕录制权限；选区可先体验，导出前需要授权。"}
    @objc func requestPermission(){
        if CGPreflightScreenCaptureAccess(){updatePermissionLabel();return}
        _=CGRequestScreenCaptureAccess()
        updatePermissionLabel()
        if !CGPreflightScreenCaptureAccess(){NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)}
    }
    func requirePermission()->Bool {
        if CGPreflightScreenCaptureAccess(){return true}
        writeState("permission-required");clearOverlays();showHome()
        statusLabel.stringValue="请点「授权屏幕录制」，在系统设置中允许「框录」，然后退出并重新打开本应用。"
        return false
    }
    @objc func selectArea(){
        guard !isBusy else{return}
        clearOverlays();home.orderOut(nil)
        NSApp.activate(ignoringOtherApps:true)
        for screen in NSScreen.screens {
            let window=OverlayWindow(contentRect:screen.frame,styleMask:.borderless,backing:.buffered,defer:false)
            window.title="框录选区";window.setAccessibilitySubrole(.standardWindow)
            window.backgroundColor = .clear;window.isOpaque=false;window.hasShadow=false;window.level = .screenSaver;window.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary];window.isReleasedWhenClosed=false
            let view=RegionView(screen:screen,owner:self);window.contentView=view;overlays.append(window);window.makeKeyAndOrderFront(nil);window.makeFirstResponder(view)
        }
        toolbar.orderOut(nil);writeState("selecting")
    }
    func activateRegion(_ view:RegionView){
        selected=view
        for w in overlays {if let v=w.contentView as? RegionView, v !== view {v.rect = .zero;v.needsDisplay=true}}
    }
    func regionChanged(_ view:RegionView){
        guard selected === view else{return}
        let size=RegionGeometry.pixelSize(view.rect,scale:view.captureScreen.backingScaleFactor)
        dimensions.stringValue="\(size.0) × \(size.1) px · \(fpsBox.titleOfSelectedItem ?? "30 fps")"
        let valid=view.rect.width>=40 && view.rect.height>=40
        captureButton.isEnabled=valid;recordButton.isEnabled=valid
        if valid {
            let screen=view.captureScreen.frame
            let desired=CGPoint(x:screen.minX+view.rect.minX,y:screen.minY+view.rect.minY-toolbar.frame.height-14)
            let x=min(max(desired.x,screen.minX+8),screen.maxX-toolbar.frame.width-8)
            let y=max(screen.minY+8,min(desired.y,screen.maxY-toolbar.frame.height-30))
            toolbar.setFrameOrigin(CGPoint(x:x,y:y));toolbar.orderFrontRegardless()
        }
        writeState(valid ? "selected":"selecting")
    }
    @objc func cancelSelection(){
        guard !isBusy else {return}
        clearOverlays();showHome();writeState("idle")
    }
    func clearOverlays(){for w in overlays{w.orderOut(nil)};overlays.removeAll();selected=nil;toolbar?.orderOut(nil)}
    @objc func openFolder(){NSWorkspace.shared.open(saveDirectory)}
    func newURL(_ suffix:String)->URL {
        let fmt=DateFormatter();fmt.dateFormat="yyyyMMdd-HHmmss-SSS"
        return saveDirectory.appendingPathComponent("框录-\(fmt.string(from:Date()))-\(UUID().uuidString.prefix(4)).\(suffix)")
    }
    func captureSetup(recordAudio:Bool=false) async throws -> (SCContentFilter,SCStreamConfiguration) {
        guard let view=selected,let number=view.captureScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else{throw NSError(domain:"框录",code:1,userInfo:[NSLocalizedDescriptionKey:"请先选择区域"])}
        let content=try await SCShareableContent.excludingDesktopWindows(false,onScreenWindowsOnly:true)
        guard let display=content.displays.first(where:{$0.displayID==number.uint32Value}) else{throw NSError(domain:"框录",code:2,userInfo:[NSLocalizedDescriptionKey:"显示器已断开，请重新框选"])}
        let own=content.applications.filter{$0.processID==ProcessInfo.processInfo.processIdentifier}
        let filter=SCContentFilter(display:display,excludingApplications:own,exceptingWindows:[])
        let config=SCStreamConfiguration()
        config.sourceRect=RegionGeometry.captureRect(view.rect,screenHeight:view.captureScreen.frame.height)
        let size=RegionGeometry.pixelSize(view.rect,scale:CGFloat(filter.pointPixelScale))
        config.width=size.0;config.height=size.1
        config.minimumFrameInterval=CMTime(value:1,timescale:Int32(fpsBox.titleOfSelectedItem?.split(separator:" ").first ?? "30") ?? 30)
        config.showsCursor=cursorBox.state == .on;config.capturesAudio=recordAudio && systemAudioBox.state == .on;config.captureMicrophone=recordAudio && microphoneBox.state == .on
        config.sampleRate=48000;config.channelCount=2;config.excludesCurrentProcessAudio=true
        config.queueDepth=5;config.pixelFormat=kCVPixelFormatType_32BGRA
        config.colorSpaceName=CGColorSpace.sRGB
        return (filter,config)
    }
    @objc func audioChanged(_ sender:NSButton){
        UserDefaults.standard.set(systemAudioBox.state == .on,forKey:"systemAudio")
        UserDefaults.standard.set(microphoneBox.state == .on,forKey:"microphone")
        writeState("settings-changed")
        if sender === microphoneBox, sender.state == .on {
            Task { _ = await ensureMicrophonePermission() }
        }
    }
    func ensureMicrophonePermission() async -> Bool {
        let status=AVCaptureDevice.authorizationStatus(for:.audio)
        if status == .authorized {return true}
        if status == .notDetermined {
            // Remove the selection overlay while the OS asks the user; never hide the system prompt.
            let visible=overlays.filter{$0.isVisible};for w in visible{w.orderOut(nil)}
            toolbar.orderOut(nil)
            let granted=await AVCaptureDevice.requestAccess(for:.audio)
            for w in visible{w.orderFrontRegardless()}
            if let v=selected {regionChanged(v)}
            if granted {writeState("microphone-authorized");return true}
        }
        statusLabel.stringValue="麦克风未授权；请在系统设置 → 隐私与安全性 → 麦克风中允许框录。关闭麦克风开关可继续仅录系统声音。"
        return false
    }
    @objc func takeScreenshot(){
        guard !isBusy,selected != nil,requirePermission() else{return}
        isBusy=true;updateButtons();clockLabel.stringValue="正在保存截图…"
        Task {do {
            let (filter,config)=try await captureSetup()
            let image=try await SCScreenshotManager.captureImage(contentFilter:filter,configuration:config)
            let rep=NSBitmapImageRep(cgImage:image)
            guard let data=rep.representation(using:.png,properties:[:]) else{throw NSError(domain:"框录",code:3)}
            let url=newURL("png");try data.write(to:url,options:.atomic)
            latestURL=url;isBusy=false;clockLabel.stringValue="截图已保存 ✓";updateButtons();writeState("screenshot-saved")
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }catch{handleError(error)}}
    }
    @objc func toggleRecording(){
        if isRecording {stopRecording();return}
        guard !isBusy else{return}
        guard selected != nil else{selectArea();return}
        guard requirePermission() else{return}
        isBusy=true;updateButtons();clockLabel.stringValue="准备录制…";writeState("starting")
        Task {do {
            if microphoneBox.state == .on, !(await ensureMicrophonePermission()) {
                isBusy=false;updateButtons();clockLabel.stringValue="未开始：麦克风未授权";writeState("microphone-permission-required");return
            }
            let (filter,config)=try await captureSetup(recordAudio:true)
            let url=newURL("mp4");outputURL=url
            let rc=SCRecordingOutputConfiguration();rc.outputURL=url;rc.videoCodecType = .h264;rc.outputFileType = .mp4
            let out=SCRecordingOutput(configuration:rc,delegate:self)
            let capture=SCStream(filter:filter,configuration:config,delegate:self)
            try capture.addRecordingOutput(out);stream=capture;output=out
            try await capture.startCapture()
        }catch{handleError(error)}}
    }
    nonisolated func recordingOutputDidStartRecording(_ recordingOutput:SCRecordingOutput){
        DispatchQueue.main.async { [self] in
            guard self.output === recordingOutput else{return}
            self.isRecording=true;self.started=Date();self.updateButtons()
            self.selected?.recording=true;self.selected?.needsDisplay=true
            for w in self.overlays {w.ignoresMouseEvents=true;if w.contentView !== self.selected {w.orderOut(nil)}}
            self.timer=Timer.scheduledTimer(withTimeInterval:0.2,repeats:true){[weak self] _ in Task { @MainActor in self?.tick() }}
            self.tick();self.writeState("recording")
        }
    }
    func tick(){
        let seconds=Int(Date().timeIntervalSince(started));let time=String(format:"%02d:%02d",seconds/60,seconds%60)
        clockLabel.stringValue="● REC \(time) · 区域已锁定"
        clockLabel.textColor = .systemRed;statusItem.button?.title=" ● \(time)"
    }
    func stopRecording(){
        guard isRecording,!finishing else{return}
        finishing=true;recordButton.isEnabled=false;clockLabel.stringValue="正在完成视频…";writeState("finishing")
        Task {do{try await stream?.stopCapture()}catch{handleError(error)}}
    }
    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput:SCRecordingOutput){
        DispatchQueue.main.async {
            guard self.output === recordingOutput else{return}
            self.latestURL=self.outputURL;self.resetRecording()
            self.clockLabel.stringValue="视频已保存 ✓";self.writeState("video-saved")
            if let url=self.latestURL {NSWorkspace.shared.activateFileViewerSelecting([url])}
            if self.pendingQuit {NSApp.terminate(nil)}
        }
    }
    nonisolated func recordingOutput(_ recordingOutput:SCRecordingOutput,didFailWithError error:Error){DispatchQueue.main.async {self.handleError(error)}}
    nonisolated func stream(_ stream:SCStream,didStopWithError error:Error){DispatchQueue.main.async {self.handleError(error)}}
    func resetRecording(){
        timer?.invalidate();timer=nil;isRecording=false;isBusy=false;finishing=false;stream=nil;output=nil
        statusItem.button?.title="";clockLabel.textColor=gold
        selected?.recording=false;selected?.needsDisplay=true
        for w in overlays{w.ignoresMouseEvents=false}
        updateButtons()
    }
    func updateButtons(){
        captureButton.isEnabled = !isBusy;reselectButton.isEnabled = !isBusy
        recordButton.title=isRecording ? "■ 停止并保存":"● 开始录制"
        recordButton.isEnabled = (!isBusy || isRecording) && !finishing
        fpsBox.isEnabled = !isBusy;cursorBox.isEnabled = !isBusy
        systemAudioBox.isEnabled = !isBusy;microphoneBox.isEnabled = !isBusy
    }
    func handleError(_ error:Error){
        resetRecording();clockLabel.stringValue="操作未完成";writeState("error",error:error.localizedDescription)
        NSApp.activate(ignoringOtherApps:true)
        let alert=NSAlert();alert.messageText="未能完成捕获";alert.informativeText=error.localizedDescription+"\n请检查系统屏幕录制权限；如刚授权，请退出并重新打开框录。";alert.runModal()
        if pendingQuit {NSApp.terminate(nil)}
    }
    @objc func displaysChanged(){
        if isRecording {stopRecording()}
        else if !isBusy {clearOverlays();showHome();statusLabel.stringValue="显示器布局已变化，请重新框选区域。"}
    }
    @objc func quit(){
        if isRecording {pendingQuit=true;stopRecording()}
        else if !isBusy {NSApp.terminate(nil)}
    }
    func writeState(_ phase:String,error:String?=nil){
        var data:[String:Any]=["phase":phase,"screenPermission":CGPreflightScreenCaptureAccess(),"timestamp":ISO8601DateFormatter().string(from:Date()),"screenCount":NSScreen.screens.count,"hotKeys":hotKeyResults,"fpsSetting":fpsBox.titleOfSelectedItem ?? "30 fps","systemAudio":systemAudioBox.state == .on,"microphone":microphoneBox.state == .on,"microphonePermission":AVCaptureDevice.authorizationStatus(for:.audio).rawValue]
        if let v=selected {
            data["regionPoints"]=["x":v.rect.minX,"y":v.rect.minY,"width":v.rect.width,"height":v.rect.height]
            data["screenOrigin"]=["x":v.captureScreen.frame.minX,"y":v.captureScreen.frame.minY]
            data["screenSize"]=["width":v.captureScreen.frame.width,"height":v.captureScreen.frame.height]
            data["backingScale"]=v.captureScreen.backingScaleFactor
        }
        if let u=latestURL{data["latestFile"]=u.path};if let e=error{data["error"]=e}
        if let bytes=try? JSONSerialization.data(withJSONObject:data,options:.prettyPrinted){try? bytes.write(to:stateDirectory.appendingPathComponent("status.json"),options:.atomic)}
    }
    func setupHotkeys(){
        let pointer=Unmanaged.passUnretained(self).toOpaque()
        var spec=EventTypeSpec(eventClass:OSType(kEventClassKeyboard),eventKind:UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(),{_,event,context in
            guard let event=event,let context=context else{return noErr}
            var key=EventHotKeyID()
            GetEventParameter(event,EventParamName(kEventParamDirectObject),EventParamType(typeEventHotKeyID),nil,MemoryLayout<EventHotKeyID>.size,nil,&key)
            let app=Unmanaged<RecorderApp>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async {if key.id==1 {app.selectArea()}else{app.toggleRecording()}}
            return noErr
        },1,&spec,pointer,nil)
        for (id,code) in [(UInt32(1),UInt32(kVK_ANSI_A)),(2,UInt32(kVK_ANSI_R))] {
            var ref:EventHotKeyRef?
            let result=RegisterEventHotKey(code,UInt32(controlKey|optionKey),EventHotKeyID(signature:0x4652414D,id:id),GetApplicationEventTarget(),0,&ref)
            hotKeyResults[String(id)]=result
            if result==noErr {hotKeys.append(ref)}
        }
    }
}

MainActor.assumeIsolated {
let app=NSApplication.shared
let delegate=RecorderApp()
app.delegate=delegate
app.setActivationPolicy(.accessory)
app.run()

}
