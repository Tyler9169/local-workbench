MainActor.assumeIsolated {
let app=NSApplication.shared
app.setActivationPolicy(.accessory)
let d=RecorderApp()
d.setupMenu();d.setupHome();d.setupToolbar()
d.displayLayout=d.currentDisplayLayout()
d.home.orderOut(nil)
for _ in 0..<100 { d.displaysChanged() }
assert(!d.home.isVisible)
d.displayLayout=[]
d.displaysChanged()
assert(!d.home.isVisible)
assert(d.statusLabel.stringValue.contains("布局已变化"))
d.showHome()
assert(d.home.isVisible)
_ = d.windowShouldClose(d.home)
assert(!d.home.isVisible)
d.displayLayout=[]
d.displaysChanged()
assert(!d.home.isVisible)
print("PASS: duplicate notifications, changed layout while hidden, explicit open, close remains hidden")
}
