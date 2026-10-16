import AppKit
import UniformTypeIdentifiers

/// 窗口根视图：模式切换放在标题栏工具条上，下面装当前页面的内容。
///
/// 菜单里的“添加图片 / 选择视频 / 运行”都先到这里，再转给当前显示的页面。
final class BadgeModeViewController: NSViewController, NSUserInterfaceValidations, NSToolbarDelegate {
    private static let modeItemIdentifier = NSToolbarItem.Identifier("勋章制作.模式")

    private enum Mode: Int, CaseIterable {
        case image
        case video

        var title: String {
            switch self {
            case .image: return "静态勋章"
            case .video: return "动态勋章"
            }
        }
    }

    private let imagePage = ImageBadgeViewController()
    private let videoPage = VideoBadgeViewController()
    private let picker = NSSegmentedControl()
    private let stage = NSView()

    private var mode: Mode = .image {
        didSet { applyMode() }
    }

    /// 挂在窗口工具条中间的模式切换；窗口那边直接取用。
    lazy var toolbarItem: NSToolbarItem = {
        picker.segmentCount = Mode.allCases.count
        for (index, option) in Mode.allCases.enumerated() {
            picker.setLabel(option.title, forSegment: index)
        }
        picker.trackingMode = .selectOne
        picker.segmentStyle = .texturedRounded
        picker.selectedSegment = 0
        picker.target = self
        picker.action = #selector(modeChanged(_:))

        let item = NSToolbarItem(itemIdentifier: Self.modeItemIdentifier)
        item.label = "模式"
        item.paletteLabel = "勋章模式"
        item.view = picker
        item.visibilityPriority = .high
        return item
    }()

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 1000, height: 720))

        addChild(imagePage)
        addChild(videoPage)
        for page in [imagePage, videoPage] {
            page.view.translatesAutoresizingMaskIntoConstraints = false
            stage.addSubview(page.view)
            NSLayoutConstraint.activate([
                page.view.topAnchor.constraint(equalTo: stage.topAnchor),
                page.view.leadingAnchor.constraint(equalTo: stage.leadingAnchor),
                page.view.trailingAnchor.constraint(equalTo: stage.trailingAnchor),
                page.view.bottomAnchor.constraint(equalTo: stage.bottomAnchor),
            ])
        }

        stage.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stage)
        NSLayoutConstraint.activate([
            stage.topAnchor.constraint(equalTo: root.topAnchor),
            stage.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stage.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stage.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])

        view = root
        applyMode()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        focusCanvas()
    }

    // MARK - 工具条

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        itemIdentifier == Self.modeItemIdentifier ? toolbarItem : nil
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, Self.modeItemIdentifier, .flexibleSpace]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    private var currentPage: BadgePageViewController {
        mode == .image ? imagePage : videoPage
    }

    private func applyMode() {
        imagePage.view.isHidden = mode != .image
        videoPage.view.isHidden = mode != .video
        picker.selectedSegment = mode == .image ? 0 : 1
        focusCanvas()
    }

    /// 焦点交给取景区，省得一打开窗口就是保存目录输入框顶着一圈蓝框、整串路径反白。
    private func focusCanvas() {
        guard let window = view.window, let canvas = currentPage.canvasView else { return }
        window.initialFirstResponder = canvas
        window.makeFirstResponder(canvas)
    }

    @objc private func modeChanged(_ sender: Any?) {
        mode = picker.selectedSegment == Mode.video.rawValue ? .video : .image
    }

    /// 按文件类型挑对应的页面打开，供“用本应用打开”和拖放共用。
    func open(url: URL) {
        mode = Self.looksLikeVideo(url) ? .video : .image
        currentPage.load(url: url)
    }

    private static func looksLikeVideo(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else {
            return false
        }
        return type.conforms(to: .movie) || type.conforms(to: .video)
    }

    // MARK: - 菜单入口

    @objc func chooseImage(_ sender: Any?) {
        mode = .image
        imagePage.chooseImage(sender)
    }

    @objc func chooseVideo(_ sender: Any?) {
        mode = .video
        videoPage.chooseVideo(sender)
    }

    @objc func runExport(_ sender: Any?) {
        currentPage.runExport(sender)
    }

    // MARK: - 菜单项可用性

    func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(runExport(_:)) {
            return currentPage.canRun
        }
        return true
    }
}
