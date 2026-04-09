import SwiftUI

/// An `L`-shaped bracket: vertical line bending into a short horizontal cap at the bottom,
/// with a rounded inner corner. `capOffset` controls how far above the bottom edge the cap lands,
/// so it aligns with the vertical centre of the last child row regardless of group height.
struct BracketShape: Shape {
    var strokeWidth: CGFloat = 1.5
    var capWidth: CGFloat = 6
    var cornerRadius: CGFloat = 3
    var capOffset: CGFloat = 6

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let capY = rect.height - capOffset
        let r = min(cornerRadius, capY / 2, capWidth / 2)
        // Start at top centre of the vertical stroke
        p.move(to: CGPoint(x: strokeWidth / 2, y: -2))
        // Vertical line down to where the corner arc begins
        p.addLine(to: CGPoint(x: strokeWidth / 2, y: capY - r))
        // Rounded corner turning right
        p.addArc(
            center: CGPoint(x: strokeWidth / 2 + r, y: capY - r),
            radius: r,
            startAngle: .degrees(180),
            endAngle: .degrees(90),
            clockwise: true
        )
        // Horizontal cap to the right
        p.addLine(to: CGPoint(x: capWidth, y: capY))
        return p
    }
}

/// Wraps child settings that depend on a parent toggle.
/// Always rendered (never hidden), but dimmed and non-interactive when `enabled` is false.
/// An `L`-bracket on the left visually groups the dependent children.
struct DependentGroup<Content: View>: View {
    let enabled: Bool
    var showBracket: Bool = true
    @ViewBuilder let content: Content

    var body: some View {
        if showBracket {
            HStack(alignment: .top, spacing: 6) {
                BracketShape()
                    .stroke(Color.secondary.opacity(0.4), lineWidth: 1.5)
                    .frame(width: 6)
                VStack(alignment: .leading, spacing: 4) {
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .allowsHitTesting(enabled)
                .opacity(enabled ? 1 : 0.6)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, 14)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                content
            }
            .allowsHitTesting(enabled)
            .opacity(enabled ? 1 : 0.6)
        }
    }
}
