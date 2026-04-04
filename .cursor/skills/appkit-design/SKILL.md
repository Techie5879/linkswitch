---
name: appkit-design
description: >-
  AppKit UI patterns for LinkSwitch: layout with NSStackView, semantic colors,
  dynamic layer updates, card views, and accessibility. Use when building or
  editing NSViewController, NSView subclasses, or any UI code in this app.
---

# AppKit design (LinkSwitch)

This app is AppKit-only. No SwiftUI.

## Spacing scale

`4 / 6 / 8 / 12 / 16 / 20` pt. Use `NSStackView.spacing` and constant offsets from this scale only; no arbitrary nudges.

## Typography

| Use | Call |
|---|---|
| Section heading | `.boldSystemFont(ofSize: NSFont.systemFontSize + 1)` |
| Body / control | `.systemFont(ofSize: NSFont.systemFontSize)` |
| Secondary / caption | `.systemFont(ofSize: NSFont.smallSystemFontSize)` |
| Emphasis | `.systemFont(ofSize: …, weight: .medium/.semibold)` |

## Colors

Always use semantic NSColor so dark mode works without extra code:
- Text: `.labelColor`, `.secondaryLabelColor`, `.tertiaryLabelColor`
- Borders: `NSColor.separatorColor`
- Selected state fill: `NSColor.controlAccentColor.withAlphaComponent(0.18)`
- Backgrounds: `NSColor.controlBackgroundColor`
- Warnings: `.systemOrange`; errors: `.systemRed`

## Dynamic color in layers

Never assign `cgColor` in `init`. Override `updateLayer()` and assign there — AppKit calls it on appearance change:

```swift
override func updateLayer() {
    super.updateLayer()
    layer?.borderColor = NSColor.separatorColor.cgColor
}
```

## Card views

Pattern used throughout: `wantsLayer = true`, `cornerRadius = 10`, `borderWidth = 1`, border color via `updateLayer()`. Content stack has 16 pt inset on all sides.

## NSStackView layout

- Set `translatesAutoresizingMaskIntoConstraints = false` on every view added with `addSubview`.
- Pin width to a parent anchor when the stack must fill width (`widthAnchor.constraint(equalTo: …)`).
- Prefer `distribution = .fillEqually` for side-by-side equal cards.
- Use a flex spacer (`NSView` with low hugging priority) to push controls to opposite ends.

## SF Symbols

```swift
NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)?
    .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 28, weight: .regular))
```

Set `contentTintColor` on `NSImageView` for semantic tinting.

## Accessibility

- Call `setAccessibilityIdentifier("preferences.<control>")` on every interactive control.
- Non-obvious icon buttons need `setAccessibilityLabel`.

## Anti-patterns

- Hard-coded `cgColor` values in `init` or `draw` (breaks dark mode).
- Fixed RGB `NSColor` where a semantic color exists.
- `layoutSubviews`-style manual frame math; use Auto Layout constraints.

## References

- [NSStackView](https://developer.apple.com/documentation/appkit/nsstackview)
- [NSLayoutConstraint / Auto Layout](https://developer.apple.com/documentation/appkit/nslayoutconstraint)
- [NSColor UI element colors](https://developer.apple.com/documentation/appkit/nscolor/ui_element_colors)
- [Supporting Dark Mode](https://developer.apple.com/documentation/appkit/supporting_dark_mode_in_your_interface)
- [NSView.updateLayer()](https://developer.apple.com/documentation/appkit/nsview/1483580-updatelayer)
- [SF Symbols — NSImage](https://developer.apple.com/documentation/appkit/nsimage/3622478-init)
- [Accessibility for AppKit](https://developer.apple.com/documentation/appkit/accessibility_for_appkit)
