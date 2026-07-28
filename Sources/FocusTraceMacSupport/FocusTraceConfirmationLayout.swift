import CoreGraphics

/// A confirmation is the only FocusTrace surface allowed to interrupt work.
/// It is horizontally centered near the top edge; passive progress and rewards
/// do not use an overlay at all.
public enum FocusTraceConfirmationLayout {
    public static let panelWidth: CGFloat = 360
    public static let panelHeight: CGFloat = 142
    public static let cornerRadius: CGFloat = 14
    public static let topInset: CGFloat = 18

    public static func frame(
        in visibleFrame: CGRect,
        size: CGSize
    ) -> CGRect {
        CGRect(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.maxY - size.height - topInset,
            width: size.width,
            height: size.height
        )
    }
}
