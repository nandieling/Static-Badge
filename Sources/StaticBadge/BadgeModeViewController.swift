import AppKit
import UniformTypeIdentifiers

/// 窗口根视图：顶上一个模式切换，下面装当前页面的内容。
///
/// 菜单里的“添加图片 / 选择视频 / 运行”都先到这里，再转给当前显示的页面。
final class BadgeModeViewController: NSViewController, NSUserInterfaceValidations {
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

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 1000, height: 760))

        picker.segmentCount = Mode.allCases.count
        for (index, option) in Mode.allCases.enumerated() {
            picker.setLabel(option.title, forSegment: index)
        }
        picker.trackingMode = .selectOne
        picker.selectedSegment = 0
        picker.target = self
        picker.action = #selector(modeChanged(_:))

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

        for control in [picker, stage] as [NSView] {
            control.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(control)
        }
        NSLayoutConstraint.activate([
            picker.topAnchor.constraint(equalTo: root.topAnchor, constant: 8),
            picker.centerXAnchor.constraint(equalTo: root.centerXAnchor),

            stage.topAnchor.constraint(equalTo: picker.bottomAnchor, constant: 8),
            stage.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stage.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stage.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])

        view = root
        applyMode()
    }

    private var currentPage: BadgePageViewController {
        mode == .image ? imagePage : videoPage
    }

    private func applyMode() {
        imagePage.view.isHidden = mode != .image
        videoPage.view.isHidden = mode != .video
        picker.selectedSegment = mode == .image ? 0 : 1
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
