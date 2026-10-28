import AppKit

/// The menu-bar template icon: a keyboard with a baby head peeking over the
/// top-right corner. Drawn in code so it stays crisp at every backing scale.
enum StatusIcon {
    static func make() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            NSColor.black.setFill()
            NSColor.black.setStroke()

            // Baby head, behind the keyboard.
            let headRect = NSRect(
                x: 13.2 - 2.9,
                y: 12.8 - 2.9,
                width: 5.8,
                height: 5.8
            )
            NSBezierPath(ovalIn: headRect).fill()

            // Hair curl.
            let curl = NSBezierPath()
            curl.lineWidth = 1.15
            curl.lineCapStyle = .round
            curl.move(to: NSPoint(x: 12.55, y: 15.35))
            curl.curve(
                to: NSPoint(x: 13.2, y: 16.95),
                controlPoint1: NSPoint(x: 11.95, y: 16.05),
                controlPoint2: NSPoint(x: 12.35, y: 16.95)
            )
            curl.curve(
                to: NSPoint(x: 13.85, y: 15.35),
                controlPoint1: NSPoint(x: 14.05, y: 16.95),
                controlPoint2: NSPoint(x: 14.45, y: 16.05)
            )
            curl.stroke()

            // Keyboard outline.
            let keyboard = NSBezierPath(
                roundedRect: NSRect(x: 1.4, y: 2.0, width: 15.2, height: 8.8),
                xRadius: 1.9,
                yRadius: 1.9
            )
            keyboard.lineWidth = 1.25
            keyboard.stroke()

            // Key caps.
            let keyRects: [NSRect] = [
                NSRect(x: 3.1, y: 7.9, width: 1.4, height: 1.1),
                NSRect(x: 5.4, y: 7.9, width: 1.4, height: 1.1),
                NSRect(x: 7.7, y: 7.9, width: 1.4, height: 1.1),
                NSRect(x: 10.0, y: 7.9, width: 1.4, height: 1.1),
                NSRect(x: 12.3, y: 7.9, width: 1.4, height: 1.1),
                NSRect(x: 3.1, y: 5.9, width: 1.4, height: 1.1),
                NSRect(x: 5.4, y: 5.9, width: 1.4, height: 1.1),
                NSRect(x: 7.7, y: 5.9, width: 1.4, height: 1.1),
                NSRect(x: 10.0, y: 5.9, width: 1.4, height: 1.1),
                NSRect(x: 12.3, y: 5.9, width: 1.4, height: 1.1)
            ]

            for rect in keyRects {
                NSBezierPath(roundedRect: rect, xRadius: 0.3, yRadius: 0.3).fill()
            }

            let spacebar = NSBezierPath(
                roundedRect: NSRect(x: 5.1, y: 3.7, width: 6.8, height: 1.2),
                xRadius: 0.35,
                yRadius: 0.35
            )
            spacebar.fill()

            return true
        }

        image.isTemplate = true
        return image
    }
}
