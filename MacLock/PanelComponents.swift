//
//  PanelComponents.swift
//  MacLock
//

import SwiftUI

/// The answer to "is my Mac being guarded right now", in one block.
///
/// The first line answers it outright rather than leaving the reader to infer it
/// from the state beneath: "watch is away" and "on a trusted network" are both
/// states in which MacLock is doing something, and only one of them is guarding.
struct StatusHeader: View {
    var status: MacLockController.Status

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: status.symbolName)
                .font(.system(size: 24))
                .foregroundStyle(status.tint)
                .symbolRenderingMode(.hierarchical)
                .frame(width: 30, alignment: .center)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(status.isGuarding ? "Guarding this Mac" : "Not guarding")
                    .font(.headline)
                Text(status.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The live smoothed signal drawn against the threshold that will lock the Mac.
///
/// Calibrating used to mean reading two numbers in two rows and holding the
/// comparison in your head. The whole judgement is "is the bar past the mark", so
/// the bar and the mark are drawn on one track, over the same dBm range the
/// threshold slider spans.
struct SignalMeter: View {
    /// Smoothed signal in dBm, or `nil` when nothing has been heard yet.
    var reading: Int?
    /// The dBm at or below which MacLock starts counting down to a lock.
    var threshold: Int
    /// The dBm the track spans, matching the threshold slider's own range.
    var range: ClosedRange<Int> = AppSettings.Limits.threshold

    private static let trackHeight: CGFloat = 8
    private static let markWidth: CGFloat = 2
    private static let markHeight: CGFloat = 16

    private var isWeak: Bool {
        guard let reading else { return false }
        return reading < threshold
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let markX = width * signalFraction(rssi: threshold, in: range)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.10))
                    .frame(height: Self.trackHeight)

                if let reading {
                    Capsule()
                        .fill(isWeak ? Color.orange : Color.green)
                        .frame(
                            width: width * signalFraction(rssi: reading, in: range),
                            height: Self.trackHeight
                        )
                }

                // Taller than the track so it reads as a mark crossing the bar
                // rather than a gap in it -- a gap disappears once the fill
                // reaches it, which is the one moment it has to be visible.
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.primary.opacity(0.65))
                    .frame(width: Self.markWidth, height: Self.markHeight)
                    .offset(x: min(max(markX - Self.markWidth / 2, 0), width - Self.markWidth))
            }
            .frame(height: Self.markHeight)
        }
        .frame(height: Self.markHeight)
        .accessibilityElement()
        .accessibilityLabel("Signal strength")
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        guard let reading else { return "No signal yet. Locks below \(threshold) dBm." }
        return "\(reading) dBm, \(isWeak ? "below" : "above") the \(threshold) dBm lock threshold."
    }
}

/// Signal strength as the system draws it everywhere else, from a dBm reading.
///
/// `variableValue` fills the bars in proportion, so one glyph carries what a number
/// in dBm does not: which of two devices is closer, at a glance, while you walk the
/// watch away from the Mac to find out which entry is yours.
struct SignalBars: View {
    var rssi: Int
    var range: ClosedRange<Int> = AppSettings.Limits.threshold

    var body: some View {
        Image(systemName: "cellularbars", variableValue: signalFraction(rssi: rssi, in: range))
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
    }
}

/// Explanatory text for the section it closes.
///
/// It is a row of the section rather than the form's `footer:`, because a footer is
/// drawn outside the group while the system draws this kind of caption inside it,
/// against the same background as the rows it explains.
struct SectionCaption: View {
    var text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
