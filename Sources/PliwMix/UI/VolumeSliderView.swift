import SwiftUI

/// Tactile macOS-style horizontal volume slider supporting optional boost range (> 1.0),
/// a 100% unity detent tick, and an optional live VU meter underlay.
public struct VolumeSliderView: View {
    public let value: Double
    public let maxValue: Double
    public let isMuted: Bool
    public let isEnabled: Bool
    public let meterLevel: Double
    public let onChanged: (Double) -> Void

    @State private var isHovering = false
    @State private var isDragging = false

    public init(
        value: Double,
        maxValue: Double = 1.0,
        isMuted: Bool = false,
        isEnabled: Bool = true,
        meterLevel: Double = 0.0,
        onChanged: @escaping (Double) -> Void
    ) {
        self.value = value
        self.maxValue = maxValue
        self.isMuted = isMuted
        self.isEnabled = isEnabled
        self.meterLevel = meterLevel
        self.onChanged = onChanged
    }

    private var fraction: Double {
        guard maxValue > 0 else { return 0 }
        return min(max(value / maxValue, 0), 1)
    }

    private var unityFraction: Double? {
        guard maxValue > 1.0 else { return nil }
        return 1.0 / maxValue
    }

    private var isBoosted: Bool {
        maxValue > 1.0 && value > 1.02 && !isMuted
    }

    public var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let trackHeight: CGFloat = (isHovering || isDragging) ? 7 : 6
            let thumbSize: CGFloat = (isHovering || isDragging) ? 15 : 13
            let usableWidth = max(width - thumbSize, 1)
            let thumbX = usableWidth * fraction
            let fillWidth = max(thumbX + thumbSize * 0.5, trackHeight)

            ZStack(alignment: .leading) {
                // Base track
                Capsule()
                    .fill(Color.primary.opacity(0.12))
                    .frame(height: trackHeight)

                // Live audio VU meter glow behind active fill
                if !isMuted && meterLevel > 0.01 {
                    let meterWidth = min(fillWidth, width * min(max(meterLevel, 0), 1))
                    Capsule()
                        .fill(Color.mint.opacity(0.32))
                        .frame(width: max(meterWidth, trackHeight), height: trackHeight)
                }

                // Active fill bar
                Capsule()
                    .fill(activeFillStyle)
                    .frame(width: min(fillWidth, width), height: trackHeight)

                // 100% unity detent marker for 0-200% sliders
                if let unity = unityFraction {
                    let tickX = thumbSize * 0.5 + usableWidth * unity
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.primary.opacity(0.38))
                        .frame(width: 1.5, height: 11)
                        .offset(x: tickX - 0.75)
                }

                // Thumb
                Circle()
                    .fill(Color(nsColor: .controlColor))
                    .overlay(
                        Circle()
                            .strokeBorder(
                                isBoosted ? Color.orange.opacity(0.9) : Color.primary.opacity(0.22),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: .black.opacity(0.22), radius: 2, y: 1)
                    .frame(width: thumbSize, height: thumbSize)
                    .offset(x: thumbX)
            }
            .frame(height: 20)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        guard isEnabled else { return }
                        isDragging = true
                        let clampedX = min(max(gesture.location.x - thumbSize * 0.5, 0), usableWidth)
                        let nextFraction = clampedX / usableWidth
                        onChanged(nextFraction * maxValue)
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.12)) {
                    isHovering = hovering
                }
            }
        }
        .frame(height: 20)
        .opacity(isEnabled ? 1.0 : 0.45)
    }

    private var activeFillStyle: AnyShapeStyle {
        if isMuted {
            return AnyShapeStyle(Color.secondary.opacity(0.4))
        }
        if isBoosted {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [Color.accentColor, Color.orange],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        }
        return AnyShapeStyle(Color.accentColor)
    }
}
