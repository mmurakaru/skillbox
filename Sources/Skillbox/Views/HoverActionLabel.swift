import SwiftUI

enum HoverActionLabelPlacement {
    case belowOrAbove
    case trailing
}

struct HoveredActionLabel {
    let text: String
    let placement: HoverActionLabelPlacement
    let anchor: Anchor<CGRect>
}

struct HoveredActionLabelPreferenceKey: PreferenceKey {
    static var defaultValue: HoveredActionLabel? { nil }

    static func reduce(value: inout HoveredActionLabel?, nextValue: () -> HoveredActionLabel?) {
        value = value ?? nextValue()
    }
}

extension View {
    /// System tooltips do not reliably appear in the menu bar panel, so the panel draws its own label.
    func hoverActionLabel(_ text: String, placement: HoverActionLabelPlacement = .belowOrAbove) -> some View {
        modifier(HoverActionLabelSource(text: text, placement: placement))
    }

    func hoverActionLabelHost() -> some View {
        overlayPreferenceValue(HoveredActionLabelPreferenceKey.self) { label in
            GeometryReader { proxy in
                if let label {
                    HoverActionLabelBubble(
                        text: label.text,
                        placement: label.placement,
                        buttonFrame: proxy[label.anchor],
                        containerSize: proxy.size
                    )
                }
            }
            .allowsHitTesting(false)
        }
    }
}

private struct HoverActionLabelSource: ViewModifier {
    let text: String
    let placement: HoverActionLabelPlacement

    @State private var isShowingLabel = false
    @State private var showLabelTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                showLabelTask?.cancel()
                guard hovering else {
                    isShowingLabel = false

                    return
                }

                showLabelTask = Task {
                    try? await Task.sleep(for: .milliseconds(350))
                    guard !Task.isCancelled else { return }

                    isShowingLabel = true
                }
            }
            .onDisappear {
                showLabelTask?.cancel()
                isShowingLabel = false
            }
            .anchorPreference(key: HoveredActionLabelPreferenceKey.self, value: .bounds) { anchor in
                isShowingLabel ? HoveredActionLabel(text: text, placement: placement, anchor: anchor) : nil
            }
    }
}

struct HoverActionLabelBubble: View {
    let text: String
    let placement: HoverActionLabelPlacement
    let buttonFrame: CGRect
    let containerSize: CGSize

    @State private var bubbleSize: CGSize = .zero

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
            .fixedSize()
            .onGeometryChange(for: CGSize.self, of: { $0.size }, action: { bubbleSize = $0 })
            .position(center)
            .opacity(bubbleSize == .zero ? 0 : 1)
            .accessibilityHidden(true)
    }

    private var center: CGPoint {
        HoverActionLabelLayout.center(
            bubbleSize: bubbleSize,
            buttonFrame: buttonFrame,
            containerSize: containerSize,
            placement: placement
        )
    }
}

enum HoverActionLabelLayout {
    static let gap: CGFloat = 4
    static let edgeInset: CGFloat = 4

    /// Below the button unless it would leave the panel, then above; always clamped inside the panel.
    static func center(bubbleSize: CGSize, buttonFrame: CGRect, containerSize: CGSize, placement: HoverActionLabelPlacement) -> CGPoint {
        switch placement {
        case .belowOrAbove:
            let belowCenterY = buttonFrame.maxY + gap + bubbleSize.height / 2
            let fitsBelow = belowCenterY + bubbleSize.height / 2 <= containerSize.height - edgeInset
            let centerY = fitsBelow ? belowCenterY : buttonFrame.minY - gap - bubbleSize.height / 2

            return CGPoint(x: clamped(buttonFrame.midX, half: bubbleSize.width / 2, limit: containerSize.width), y: centerY)
        case .trailing:
            let centerX = buttonFrame.maxX + gap + bubbleSize.width / 2

            return CGPoint(
                x: clamped(centerX, half: bubbleSize.width / 2, limit: containerSize.width),
                y: clamped(buttonFrame.midY, half: bubbleSize.height / 2, limit: containerSize.height)
            )
        }
    }

    private static func clamped(_ center: CGFloat, half: CGFloat, limit: CGFloat) -> CGFloat {
        let lowest = half + edgeInset

        return min(max(center, lowest), max(limit - half - edgeInset, lowest))
    }
}

/// Icon-only row action with a tinted hover state, a hover label, and a matching accessibility label.
struct RowIconActionButton: View {
    let systemName: String
    let tint: Color
    let label: String
    /// Longer explanation for the system tooltip; the hover label stays short so it fits the panel.
    var detail: String?
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isHovering ? tint : Color.secondary)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isHovering ? tint.opacity(0.15) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(detail ?? label)
        .accessibilityLabel(label)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.1)) { isHovering = hovering }
        }
        .hoverActionLabel(label)
    }
}
