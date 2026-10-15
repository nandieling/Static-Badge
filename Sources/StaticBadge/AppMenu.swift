import AppKit

/// 手工搭主菜单：一个 Mac 应用至少要有应用菜单、编辑菜单和窗口菜单。
enum AppMenu {
    static func make(controller: MainViewController, delegate: AppDelegate) -> NSMenu {
        let mainMenu = NSMenu()
        mainMenu.addItem(appMenuItem(delegate: delegate))
        mainMenu.addItem(fileMenuItem(controller: controller))
        mainMenu.addItem(editMenuItem())
        mainMenu.addItem(windowMenuItem())
        return mainMenu
    }

    private static func appMenuItem(delegate: AppDelegate) -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: AppInfo.title)
        item.submenu = menu

        let about = NSMenuItem(title: "关于 \(AppInfo.title)",
                               action: #selector(AppDelegate.showAboutPanel(_:)), keyEquivalent: "")
        about.target = delegate
        menu.addItem(about)
        menu.addItem(.separator())

        let services = NSMenuItem(title: "服务", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: "服务")
        services.submenu = servicesMenu
        NSApp.servicesMenu = servicesMenu
        menu.addItem(services)
        menu.addItem(.separator())

        menu.addItem(withTitle: "隐藏 \(AppInfo.title)",
                     action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = menu.addItem(withTitle: "隐藏其他",
                                      action: #selector(NSApplication.hideOtherApplications(_:)),
                                      keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(withTitle: "显示全部",
                     action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 \(AppInfo.title)",
                     action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return item
    }

    private static func fileMenuItem(controller: MainViewController) -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "文件")
        item.submenu = menu

        let load = NSMenuItem(title: "添加图片…", action: #selector(MainViewController.chooseImage(_:)),
                              keyEquivalent: "o")
        load.target = controller
        menu.addItem(load)

        let run = NSMenuItem(title: "运行", action: #selector(MainViewController.runExport(_:)),
                             keyEquivalent: "r")
        run.target = controller
        menu.addItem(run)

        menu.addItem(.separator())
        menu.addItem(withTitle: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        return item
    }

    private static func editMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "编辑")
        item.submenu = menu

        menu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = menu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(.separator())
        menu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        return item
    }

    private static func windowMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "窗口")
        item.submenu = menu

        menu.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)),
                     keyEquivalent: "m")
        menu.addItem(withTitle: "前置全部窗口", action: #selector(NSApplication.arrangeInFront(_:)),
                     keyEquivalent: "")
        NSApp.windowsMenu = menu
        return item
    }
}
