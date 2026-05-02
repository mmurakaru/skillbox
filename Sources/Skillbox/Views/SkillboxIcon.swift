import SwiftUI
import AppKit

@MainActor
enum MenuBarIcon {
    static let nsImage: NSImage = {
        let viewBoxWidth: CGFloat = 428
        let viewBoxHeight: CGFloat = 748
        let height: CGFloat = 18
        let width: CGFloat = height * (viewBoxWidth / viewBoxHeight)

        let image = NSImage(size: NSSize(width: width, height: height), flipped: true) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.scaleBy(x: rect.width / viewBoxWidth, y: rect.height / viewBoxHeight)

            let anchors: [(CGFloat, CGFloat)] = [
                (163, 132.335),
                (0,   287.335),
                (163, 452.335),
                (0,   615.335),
            ]
            let rectSize: CGFloat = 187.149
            let cornerRadius: CGFloat = 8

            ctx.setFillColor(NSColor.black.cgColor)
            for (x, y) in anchors {
                ctx.saveGState()
                ctx.translateBy(x: x, y: y)
                ctx.rotate(by: -.pi / 4)
                let path = CGPath(
                    roundedRect: CGRect(x: 0, y: 0, width: rectSize, height: rectSize),
                    cornerWidth: cornerRadius,
                    cornerHeight: cornerRadius,
                    transform: nil
                )
                ctx.addPath(path)
                ctx.fillPath()
                ctx.restoreGState()
            }
            return true
        }
        image.isTemplate = true
        return image
    }()
}
