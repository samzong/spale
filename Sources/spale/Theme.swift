import AppKit
import CoreText

extension NSColor {
    convenience init(hex: String) {
        let raw = UInt64(hex, radix: 16) ?? 0
        let alpha = hex.count == 8 ? CGFloat(raw & 255) / 255 : 1
        let rgb = hex.count == 8 ? raw >> 8 : raw
        self.init(srgbRed: CGFloat((rgb >> 16) & 255) / 255, green: CGFloat((rgb >> 8) & 255) / 255, blue: CGFloat(rgb & 255) / 255, alpha: alpha)
    }
}

enum Theme {
    static func color(_ light: String, _ dark: String) -> NSColor {
        NSColor(name: nil) { appearance in NSColor(hex: appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light) }
    }
    static let page = color("e7e8eb", "242527")
    static let bg = color("f5f5f7", "161719")
    static let fg = color("24292f", "e6edf3")
    static let strong = color("292d33", "e6e7e9")
    static let muted = color("656970", "9c9ea3")
    static let mark = color("9c713f", "e9c08a")
    static let soft = color("555960", "c3c4c7")
    static let line = color("0000000d", "ffffff10")
    static let selection = color("0000000d", "ffffff1a")
    static let add = color("116329", "8dbfac")
    static let remove = color("a40e26", "e7a39d")
    static let modify = color("9a6700", "c7ad79")
    static let addBG = color("1163290c", "3fb9500e")
    static let removeBG = color("cf222e09", "ff7b720b")
    static let addWord = color("11632920", "3fb95027")
    static let removeWord = color("cf222e1c", "ff7b7225")
    static let keyword = color("8250df", "d2a8ff")
    static let number = color("0969da", "79c0ff")
    static func fira(_ size: CGFloat) -> NSFont { NSFont(name: "FiraCode-Light", size: size) ?? .monospacedSystemFont(ofSize: size, weight: .light) }
    static var code: NSFont { fira(12) }
    static var wordmark: NSFont { fira(22) }
    static let ui = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
    static let uiMedium = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
    static let row = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
    static let heading = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
    static let message = NSFont.monospacedDigitSystemFont(ofSize: 15, weight: .regular)
    static var reducedMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    static func registerFonts() {
        guard let resources = Bundle.main.resourceURL, let enumerator = FileManager.default.enumerator(at: resources, includingPropertiesForKeys: nil) else { return }
        for case let url as URL in enumerator where ["ttf", "otf"].contains(url.pathExtension) {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

class Surface: NSView {
    var fill: NSColor = Theme.bg { didSet { needsDisplay = true } }
    var topBorder = false
    var rightBorder = false
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        fill.setFill(); bounds.fill(); Theme.line.setFill()
        if topBorder { NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill() }
        if rightBorder { NSRect(x: bounds.width - 1, y: 0, width: 1, height: bounds.height).fill() }
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
}

func label(_ value: String, color: NSColor = Theme.fg, font: NSFont = Theme.ui) -> NSTextField {
    let field = NSTextField(labelWithString: value)
    field.font = font; field.textColor = color; field.lineBreakMode = .byTruncatingMiddle
    return field
}

final class ActionButton: NSButton {
    var actionBlock: (() -> Void)?
    init(_ title: String, symbol: String? = nil, action: @escaping () -> Void) {
        super.init(frame: .zero)
        self.title = title; self.actionBlock = action; target = self; self.action = #selector(invoke)
        isBordered = false; focusRingType = .none; font = Theme.ui; contentTintColor = Theme.soft
        if let symbol { image = NSImage(systemSymbolName: symbol, accessibilityDescription: title); self.title = ""; toolTip = title }
        setAccessibilityLabel(title)
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func invoke() { actionBlock?() }
}

final class ShapeView: NSView {
    override var isFlipped: Bool { true }
    let shape = CAShapeLayer()
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true; layer?.addSublayer(shape)
        shape.frame = bounds; shape.fillColor = nil; shape.lineWidth = 1.5; shape.lineCap = .round; shape.lineJoin = .round
    }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); updateColor() }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateColor() }
    private func updateColor() { effectiveAppearance.performAsCurrentDrawingAppearance { shape.strokeColor = Theme.muted.cgColor } }
}

final class ShavingView: NSView {
    override var isFlipped: Bool { true }
    let stroke = CAShapeLayer()
    var progress: CGFloat = 1 { didSet { stroke.strokeEnd = progress } }
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true; layer?.addSublayer(stroke)
        stroke.fillColor = nil; stroke.lineCap = .round; stroke.lineJoin = .round
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 6, y: 30)); path.addLine(to: CGPoint(x: 22, y: 30))
        path.addRelativeArc(center: CGPoint(x: 22, y: 21), radius: 9, startAngle: .pi / 2, delta: -.pi)
        path.addRelativeArc(center: CGPoint(x: 22, y: 18), radius: 6, startAngle: -.pi / 2, delta: -.pi)
        path.addRelativeArc(center: CGPoint(x: 22, y: 20.5), radius: 3.5, startAngle: .pi / 2, delta: -.pi)
        path.addRelativeArc(center: CGPoint(x: 22, y: 19), radius: 2, startAngle: -.pi / 2, delta: -.pi / 2)
        let scale = min(bounds.width, bounds.height) / 40
        let center = path.boundingBoxOfPath
        var transform = CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: bounds.midX - center.midX * scale, ty: bounds.midY - center.midY * scale)
        stroke.path = path.copy(using: &transform); stroke.lineWidth = 1.3 * scale
        effectiveAppearance.performAsCurrentDrawingAppearance { stroke.strokeColor = Theme.mark.cgColor }
        stroke.frame = bounds
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsLayout = true }
    func drawStroke() {
        progress = 1
        let animation = CABasicAnimation(keyPath: "strokeEnd")
        animation.fromValue = 0; animation.toValue = 1; animation.duration = 0.9
        animation.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.8, 0.2, 1)
        stroke.add(animation, forKey: "opening")
    }
}
