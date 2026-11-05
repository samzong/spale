import AppKit

final class WindowBarScrollView: NSScrollView {
    override var scrollerStyle: NSScroller.Style {
        get { super.scrollerStyle }
        set { super.scrollerStyle = .overlay }
    }
}

final class WindowBar: Surface {
    static weak var activeBar: WindowBar?
    let scrollView = WindowBarScrollView()
    let content = Surface()
    weak var currentButton: ActionButton?
    var contentWidth: CGFloat = 0
    var windowOrder: [ObjectIdentifier] = []
    var currentWindow: ObjectIdentifier?
    var lastWidth: CGFloat = -1

    override init(frame: NSRect) {
        super.init(frame: frame)
        topBorder = true
        scrollView.documentView = content
        scrollView.hasHorizontalScroller = true; scrollView.hasVerticalScroller = false
        scrollView.horizontalScroller?.controlSize = .mini
        scrollView.scrollerStyle = .overlay; scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false; scrollView.contentView.drawsBackground = false
        addSubview(scrollView)
    }
    required init?(coder: NSCoder) { fatalError() }

    func update(_ workspaces: [Workspace], current: Workspace) {
        let order = workspaces.map(ObjectIdentifier.init)
        let selected = ObjectIdentifier(current)
        let reveal = order != windowOrder || selected != currentWindow
        windowOrder = order; currentWindow = selected
        content.subviews.forEach { $0.removeFromSuperview() }
        currentButton = nil
        var x: CGFloat = 8
        for workspace in workspaces {
            let button = ActionButton(workspace.displayName + (workspace.edited ? "  ●" : "")) { [weak workspace] in workspace?.show() }
            button.cell?.usesSingleLineMode = true
            let width = button.intrinsicContentSize.width + 32
            button.frame = NSRect(x: x, y: 3, width: width, height: 24)
            if workspace === current {
                currentButton = button
                let selected = Surface(frame: button.frame)
                selected.fill = Theme.selection; selected.wantsLayer = true; selected.layer?.cornerRadius = 8
                content.addSubview(selected)
            }
            content.addSubview(button); x += width
        }
        contentWidth = x + 8
        layoutContents(reveal: reveal)
    }

    func layoutContents(reveal: Bool = false) {
        let widthChanged = lastWidth != bounds.width
        lastWidth = bounds.width
        let origin = scrollView.contentView.bounds.origin
        scrollView.frame = NSRect(x: 0, y: 1, width: bounds.width, height: max(0, bounds.height - 1))
        content.frame = NSRect(x: 0, y: 0, width: max(bounds.width, contentWidth), height: scrollView.bounds.height)
        if reveal || widthChanged { revealCurrent() }
        else {
            let clip = scrollView.contentView
            let target = NSRect(origin: origin, size: clip.bounds.size)
            clip.scroll(to: clip.constrainBoundsRect(target).origin)
            scrollView.reflectScrolledClipView(clip)
        }
    }

    func becomeCurrent() {
        guard Self.activeBar !== self else { return }
        Self.activeBar = self
        revealCurrent()
    }

    func revealCurrent() {
        guard let button = currentButton else { return }
        var target = button.frame.insetBy(dx: -8, dy: 0)
        target.size.width = min(target.width, scrollView.contentSize.width)
        content.scrollToVisible(target)
    }
}
