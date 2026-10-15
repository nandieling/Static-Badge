import AppKit
import StaticBadgeCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var controller: MainViewController?
    /// 启动时随“打开”事件一起送进来的图片，等界面建好后补上。
    private var pendingImageURL: URL?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = MainViewController()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.contentViewController = controller
        window.title = AppInfo.title
        window.setContentSize(NSSize(width: 1000, height: 700))
        window.minSize = NSSize(width: 520, height: 420)
        window.isReleasedWhenClosed = false
        window.center()

        self.controller = controller
        self.window = window
        NSApp.mainMenu = AppMenu.make(controller: controller, delegate: self)

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        if let pendingImageURL {
            self.pendingImageURL = nil
            controller.load(url: pendingImageURL)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// AppKit 可能在 `applicationDidFinishLaunching` 之前就派发“打开”事件，
    /// 所以这里要先假设界面还没建好。
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        guard let controller else {
            pendingImageURL = url
            return
        }
        controller.load(url: url)
    }

    @objc func showAboutPanel(_ sender: Any?) {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: AppInfo.title,
            .applicationVersion: AppInfo.shortVersion,
            .credits: AppInfo.credits,
        ])
        NSApp.activate(ignoringOtherApps: true)
    }
}
