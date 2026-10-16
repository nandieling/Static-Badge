import AppKit
import StaticBadgeCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var controller: BadgeModeViewController?
    /// 启动时随“打开”事件一起送进来的文件，等界面建好后补上。
    private var pendingURL: URL?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = BadgeModeViewController()
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
        window.toolbar = makeToolbar(controller: controller)

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // 命令行里直接给文件路径时也当成“打开”处理，开发和脚本调用都方便。
        if pendingURL == nil {
            pendingURL = CommandLine.arguments.dropFirst()
                .first { $0.hasPrefix("/") && FileManager.default.fileExists(atPath: $0) }
                .map { URL(fileURLWithPath: $0) }
        }

        if let pendingURL {
            self.pendingURL = nil
            controller.open(url: pendingURL)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// 模式切换放在标题栏正中，内容区就能整块留给表单和画布。
    private func makeToolbar(controller: BadgeModeViewController) -> NSToolbar {
        let toolbar = NSToolbar(identifier: "勋章制作.主工具条")
        toolbar.delegate = controller
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        if #available(macOS 11.0, *) {
            toolbar.centeredItemIdentifier = controller.toolbarItem.itemIdentifier
        }
        return toolbar
    }

    /// AppKit 可能在 `applicationDidFinishLaunching` 之前就派发“打开”事件，
    /// 所以这里要先假设界面还没建好。
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        guard let controller else {
            pendingURL = url
            return
        }
        controller.open(url: url)
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
