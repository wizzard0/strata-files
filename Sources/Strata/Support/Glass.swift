import AppKit

/// Liquid Glass arrived with macOS 26. On macOS 15 nothing is glass, and Strata's floating panels sit on the material
/// that system floats its own panels on.
package enum Glass {
    package static func panel() -> NSView {
        if #available(macOS 26, *) { return NSGlassEffectView() }
        return MaterialPanel()
    }
}

extension NSView {
    package var isGlass: Bool {
        if #available(macOS 26, *) { return self is NSGlassEffectView }
        return false
    }

    /// Glass's own tint. Anything else has none and ignores one it is given.
    package var glassTint: NSColor? {
        get {
            if #available(macOS 26, *) { return (self as? NSGlassEffectView)?.tintColor }
            return nil
        }
        set {
            if #available(macOS 26, *) { (self as? NSGlassEffectView)?.tintColor = newValue }
        }
    }

    /// The corner radius of a view made by `Glass.panel()`.
    package var panelCornerRadius: CGFloat {
        get {
            if #available(macOS 26, *), let glass = self as? NSGlassEffectView { return glass.cornerRadius }
            return (self as? MaterialPanel)?.cornerRadius ?? 0
        }
        set {
            if #available(macOS 26, *), let glass = self as? NSGlassEffectView { glass.cornerRadius = newValue }
            (self as? MaterialPanel)?.cornerRadius = newValue
        }
    }

    /// What a view made by `Glass.panel()` shows, filling it.
    package var panelContent: NSView? {
        get {
            if #available(macOS 26, *), let glass = self as? NSGlassEffectView { return glass.contentView }
            return (self as? MaterialPanel)?.content
        }
        set {
            if #available(macOS 26, *), let glass = self as? NSGlassEffectView { glass.contentView = newValue }
            (self as? MaterialPanel)?.content = newValue
        }
    }
}

/// macOS 15's stand-in for a glass panel: the popover material with rounded corners, sized by what it shows.
final class MaterialPanel: NSVisualEffectView {
    var cornerRadius: CGFloat = 0 {
        didSet { layer?.cornerRadius = cornerRadius }
    }

    var content: NSView? {
        didSet {
            oldValue?.removeFromSuperview()
            guard let content else { return }
            content.translatesAutoresizingMaskIntoConstraints = false
            addSubview(content)
            NSLayoutConstraint.activate([
                content.leadingAnchor.constraint(equalTo: leadingAnchor),
                content.trailingAnchor.constraint(equalTo: trailingAnchor),
                content.topAnchor.constraint(equalTo: topAnchor),
                content.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }
    }

    init() {
        super.init(frame: .zero)
        material = .popover
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}
