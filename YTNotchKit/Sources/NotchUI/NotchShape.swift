import SwiftUI

/// The one shape every notch state is drawn with, top-centred in its frame: a body with
/// continuous bottom corners, and a concave flare on each side where it meets the top edge
/// (design spec, "Corner geometry"). All four values animate together.
public struct NotchShape: Shape {
    public var outline: NotchOutline

    public init(_ outline: NotchOutline) {
        self.outline = outline
    }

    public var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get {
            AnimatablePair(AnimatablePair(outline.width, outline.height), AnimatablePair(outline.bottomRadius, outline.flare))
        }
        set {
            outline = NotchOutline(
                width: newValue.first.first, height: newValue.first.second,
                bottomRadius: newValue.second.first, flare: newValue.second.second
            )
        }
    }

    public func path(in rect: CGRect) -> Path {
        Self.path(outline, topCentre: CGPoint(x: rect.midX, y: rect.minY))
    }

    /// The outline with its top edge centred on `topCentre`, in a y-down space.
    static func path(_ outline: NotchOutline, topCentre: CGPoint) -> Path {
        let width = max(0, outline.width)
        let height = max(0, outline.height)
        let radius = min(max(0, outline.bottomRadius), height, width / 2)
        // The flare's arc ends where the straight side begins, so it fits above the corner.
        let flare = min(max(0, outline.flare), max(0, height - radius))
        let left = topCentre.x - width / 2
        let top = topCentre.y

        let body = UnevenRoundedRectangle(
            cornerRadii: RectangleCornerRadii(topLeading: 0, bottomLeading: radius, bottomTrailing: radius, topTrailing: 0),
            style: .continuous
        ).path(in: CGRect(x: left, y: top, width: width, height: height))
        guard flare > 0 else { return body }

        // Each flare fills the square between the side and the top edge, less a quarter
        // circle of radius `flare` centred out in the menu bar, so it curves into the edge.
        var flares = Path()
        flares.move(to: CGPoint(x: left - flare, y: top))
        flares.addLine(to: CGPoint(x: left, y: top))
        flares.addLine(to: CGPoint(x: left, y: top + flare))
        flares.addArc(center: CGPoint(x: left - flare, y: top + flare), radius: flare,
                      startAngle: .degrees(0), endAngle: .degrees(-90), clockwise: true)
        flares.closeSubpath()
        let right = left + width
        flares.move(to: CGPoint(x: right + flare, y: top))
        flares.addLine(to: CGPoint(x: right, y: top))
        flares.addLine(to: CGPoint(x: right, y: top + flare))
        flares.addArc(center: CGPoint(x: right + flare, y: top + flare), radius: flare,
                      startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        flares.closeSubpath()
        // One outline, so no seam shows where the flares meet the body.
        return body.union(flares)
    }
}
