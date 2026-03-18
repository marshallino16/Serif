import SwiftUI

/// Multicolor Google "G" logo drawn purely in SwiftUI.
struct GoogleLogo: View {
    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: size / 2, y: size / 2)
            let outer = size / 2
            let inner = size * 0.28
            let barHeight = size * 0.16

            ZStack {
                // Blue arc (right / bottom-right) — 315° to 50°
                arcSegment(center: center, outer: outer, inner: inner, startAngle: -14, endAngle: 50)
                    .fill(Color(hex: "#4285F4"))

                // Green arc (bottom) — 50° to 150°
                arcSegment(center: center, outer: outer, inner: inner, startAngle: 50, endAngle: 150)
                    .fill(Color(hex: "#34A853"))

                // Yellow arc (left / bottom-left) — 150° to 230°
                arcSegment(center: center, outer: outer, inner: inner, startAngle: 150, endAngle: 230)
                    .fill(Color(hex: "#FBBC05"))

                // Red arc (top) — 230° to 315°
                arcSegment(center: center, outer: outer, inner: inner, startAngle: 230, endAngle: 315)
                    .fill(Color(hex: "#EA4335"))

                // Horizontal bar (the crossbar of the "G") — blue
                Rectangle()
                    .fill(Color(hex: "#4285F4"))
                    .frame(width: size * 0.52, height: barHeight)
                    .position(x: center.x + size * 0.04, y: center.y)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func arcSegment(center: CGPoint, outer: CGFloat, inner: CGFloat, startAngle: Double, endAngle: Double) -> Path {
        var path = Path()
        path.addArc(center: center, radius: outer, startAngle: .degrees(startAngle), endAngle: .degrees(endAngle), clockwise: false)
        path.addArc(center: center, radius: inner, startAngle: .degrees(endAngle), endAngle: .degrees(startAngle), clockwise: true)
        path.closeSubpath()
        return path
    }
}
