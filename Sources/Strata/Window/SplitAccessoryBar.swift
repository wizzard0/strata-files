import AppKit

/// A bar above or below a split view item's content: the status bar, the search scope, a notice, the sidebar's footer.
/// macOS 26 holds it as the item's accessory, over content that scrolls beneath it. macOS 15 has no such accessories:
/// there it is stacked with the content. Its view is made on first use, as a view controller's is.
class SplitAccessoryBar: NSObject {
    private var loaded: NSView?
    fileprivate var hiddenChanged: (() -> Void)?

    var view: NSView {
        get {
            loadViewIfNeeded()
            guard let loaded else { preconditionFailure("\(type(of: self)).loadView() set no view") }
            return loaded
        }
        set { loaded = newValue }
    }

    var isHidden = false {
        didSet {
            if isHidden != oldValue { hiddenChanged?() }
        }
    }

    /// Overridden to assign `view`.
    func loadView() {}

    func loadViewIfNeeded() {
        if loaded == nil { loadView() }
    }
}

enum SplitAccessories {
    /// What the item shows: `controller` itself on macOS 26, where `attach` adds the bars; stacked between them on 15.
    static func content(_ controller: NSViewController, top: [SplitAccessoryBar], bottom: [SplitAccessoryBar]) -> NSViewController {
        if #available(macOS 26, *) { return controller }
        return StackedSplitAccessories(controller, top: top, bottom: bottom)
    }

    static func attach(top: [SplitAccessoryBar], bottom: [SplitAccessoryBar], to item: NSSplitViewItem) {
        guard #available(macOS 26, *) else { return }
        for bar in top { item.addTopAlignedAccessoryViewController(SplitAccessoryHost(bar)) }
        for bar in bottom { item.addBottomAlignedAccessoryViewController(SplitAccessoryHost(bar)) }
    }
}

@available(macOS 26, *)
private final class SplitAccessoryHost: NSSplitViewItemAccessoryViewController {
    private let bar: SplitAccessoryBar

    init(_ bar: SplitAccessoryBar) {
        self.bar = bar
        super.init(nibName: nil, bundle: nil)
        isHidden = bar.isHidden
        bar.hiddenChanged = { [weak self, unowned bar] in self?.isHidden = bar.isHidden }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        view = bar.view
    }
}

/// macOS 15: the bars above the content start under the toolbar, and the content runs beneath the toolbar only while
/// none of them shows, as it does on its own.
private final class StackedSplitAccessories: NSViewController {
    private let content: NSViewController
    private let top: [SplitAccessoryBar]
    private let bottom: [SplitAccessoryBar]
    private var underToolbar: NSLayoutConstraint?
    private var underBars: NSLayoutConstraint?

    init(_ content: NSViewController, top: [SplitAccessoryBar], bottom: [SplitAccessoryBar]) {
        self.content = content
        self.top = top
        self.bottom = bottom
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let root = NSView()
        let above = Self.stack(top)
        let below = Self.stack(bottom)
        addChild(content)
        for part in [content.view, above, below] {
            part.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(part)
            part.leadingAnchor.constraint(equalTo: root.leadingAnchor).isActive = true
            part.trailingAnchor.constraint(equalTo: root.trailingAnchor).isActive = true
        }
        underToolbar = content.view.topAnchor.constraint(equalTo: root.topAnchor)
        underBars = content.view.topAnchor.constraint(equalTo: above.bottomAnchor)
        NSLayoutConstraint.activate([
            above.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor),
            content.view.bottomAnchor.constraint(equalTo: below.topAnchor),
            below.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        view = root
        for bar in top + bottom {
            bar.hiddenChanged = { [weak self, unowned bar] in
                bar.view.isHidden = bar.isHidden
                self?.placeContent()
            }
        }
        placeContent()
    }

    private func placeContent() {
        let barShows = top.contains { !$0.isHidden }
        underToolbar?.isActive = !barShows
        underBars?.isActive = barShows
    }

    /// Hidden bars take no room; with none showing the stack has no height.
    private static func stack(_ bars: [SplitAccessoryBar]) -> NSStackView {
        let stack = NSStackView(views: bars.map(\.view))
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 0
        for bar in bars { bar.view.isHidden = bar.isHidden }
        let empty = stack.heightAnchor.constraint(equalToConstant: 0)
        empty.priority = .defaultLow
        empty.isActive = true
        return stack
    }
}
