import SwiftUI
import ModelSwitchboardCore

struct BenchmarkColumnWidths {
    let profile: CGFloat
    let ttft: CGFloat
    let decode: CGFloat
    let e2e: CGFloat
    let rss: CGFloat

    static func forTotalWidth(_ totalWidth: CGFloat) -> Self {
        let dividerWidthTotal: CGFloat = 4
        let usable = max(200, totalWidth - dividerWidthTotal)
        let profile = floor(usable * 0.30)
        let ttft = floor(usable * 0.15)
        let decode = floor(usable * 0.19)
        let e2e = floor(usable * 0.16)
        let rss = max(28, usable - profile - ttft - decode - e2e)
        return Self(profile: profile, ttft: ttft, decode: decode, e2e: e2e, rss: rss)
    }
}

struct BenchmarkTableComponents {
    static func headerCell(_ text: String, width: CGFloat, align: Alignment) -> some View {
        Text(text)
            .font(.caption2.bold())
            .foregroundStyle(Color.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .multilineTextAlignment(align == .leading ? .leading : .center)
            .frame(width: width, alignment: align)
    }

    static func valueCell(_ text: String, width: CGFloat, align: Alignment) -> some View {
        Text(text)
            .font(.caption2.monospacedDigit())
            .foregroundStyle(Color.primary)
            .lineLimit(1)
            .truncationMode(.tail)
            .multilineTextAlignment(align == .leading ? .leading : .center)
            .frame(width: width, alignment: align)
    }

    static func tableDivider() -> some View {
        Rectangle()
            .fill(.white.opacity(0.10))
            .frame(width: 1, height: 16)
    }

    static func metricPill(title: String, value: String) -> some View {
        VStack(alignment: .center, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
            Text(value)
                .font(.caption.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .center)
    }

    static func compactMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption2.bold())
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
