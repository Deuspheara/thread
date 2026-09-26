import Foundation
import ThreadDomain

/// Keeps restored geometry on a currently available display after monitor changes.
struct WindowGeometry {
    func frame(_ saved: WindowFrame, screens: [WindowFrame]) -> WindowFrame? {
        guard valid(saved), let first = screens.first, screens.allSatisfy(valid) else { return nil }
        let rectangle = rect(saved)
        let screen = screens.max { overlap(rectangle, rect($0)) < overlap(rectangle, rect($1)) } ?? first
        let width = min(saved.width, screen.width), height = min(saved.height, screen.height)
        return WindowFrame(x: max(screen.x, min(saved.x, screen.x + screen.width - width)),
                           y: max(screen.y, min(saved.y, screen.y + screen.height - height)), width: width, height: height)
    }
    private func valid(_ frame: WindowFrame) -> Bool {
        [frame.x, frame.y, frame.width, frame.height].allSatisfy(\.isFinite) && frame.width > 0 && frame.height > 0
    }
    private func rect(_ frame: WindowFrame) -> CGRect { CGRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height) }
    private func overlap(_ lhs: CGRect, _ rhs: CGRect) -> Double {
        let intersection = lhs.intersection(rhs)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }
}
