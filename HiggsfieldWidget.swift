import WidgetKit
import SwiftUI
import AppKit

private extension Color {
    /// Higgsfield brand lime (`--color-lime`). Darkened in light mode, where
    /// the neon original is unreadable as text. Mirrors the app's definition —
    /// the widget links only the Foundation-only core, not the app sources.
    static let hfLime = Color(nsColor: NSColor(name: "hfLime") { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 209 / 255, green: 254 / 255, blue: 23 / 255, alpha: 1)   // #D1FE17
            : NSColor(srgbRed: 104 / 255, green: 133 / 255, blue: 0 / 255, alpha: 1)    // #688500
    })

    static let hfLimeSolid = Color(red: 209 / 255, green: 254 / 255, blue: 23 / 255)
}

private func fmt(_ v: Double) -> String {
    v == v.rounded() ? String(format: "%.0f", v) : String(format: "%.1f", v)
}

// MARK: - Timeline

struct CreditsEntry: TimelineEntry {
    let date: Date
    let snapshot: CreditsSnapshot
}

struct CreditsProvider: TimelineProvider {
    func placeholder(in context: Context) -> CreditsEntry {
        CreditsEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (CreditsEntry) -> Void) {
        completion(CreditsEntry(date: Date(), snapshot: SharedStore.read() ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CreditsEntry>) -> Void) {
        let snap = SharedStore.read() ?? .placeholder
        let now = Date()
        // The main app pushes reloads after each fetch; this is just a safety
        // net so the widget stays roughly fresh if the app is not running.
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: now) ?? now.addingTimeInterval(900)
        completion(Timeline(entries: [CreditsEntry(date: now, snapshot: snap)], policy: .after(next)))
    }
}

// MARK: - Pieces

/// The extension has its own bundle, so it carries its own copy of the glyph.
private let brandLogo: NSImage? = {
    guard let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "pdf") else { return nil }
    return NSImage(contentsOf: url)
}()

private struct Header: View {
    var body: some View {
        HStack(spacing: 5) {
            Group {
                if let logo = brandLogo {
                    Image(nsImage: logo)
                        .resizable()
                        .renderingMode(.template)
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 12)
                } else {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 11))
                }
            }
            .foregroundColor(.hfLime)
            Text("Higgsfield")
                .font(.system(size: 12, weight: .semibold))
            Spacer()
        }
    }
}

private func creditsColor(_ snap: CreditsSnapshot) -> Color {
    snap.credits < snap.warnBelow ? .red : .hfLime
}

private struct ModelMini: View {
    let model: CreditsSnapshot.Model
    let maxCredits: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(model.name)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(fmt(model.credits)) cr · \(model.generations)")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.10))
                    Capsule()
                        .fill(LinearGradient(colors: [Color.hfLimeSolid.opacity(0.65), .hfLime],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(3, geo.size.width * CGFloat(maxCredits > 0 ? model.credits / maxCredits : 0)))
                }
            }
            .frame(height: 5)
        }
    }
}

// MARK: - Small

private struct SmallView: View {
    let snapshot: CreditsSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Header()
            Spacer(minLength: 0)
            Text("Credits")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            Text(fmt(snapshot.credits))
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundColor(creditsColor(snapshot))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            if !snapshot.plan.isEmpty {
                Text(snapshot.plan.capitalized)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.hfLime)
            }
        }
    }
}

// MARK: - Medium

private struct MediumView: View {
    let snapshot: CreditsSnapshot

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Header()
                Spacer(minLength: 0)
                Text("Credits")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                Text(fmt(snapshot.credits))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(creditsColor(snapshot))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                if !snapshot.plan.isEmpty {
                    Text(snapshot.plan.capitalized)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.hfLime)
                }
            }
            .frame(width: 118, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                Text(snapshot.windowLabel)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                let maxCr = snapshot.topModels.map(\.credits).max() ?? 1
                ForEach(Array(snapshot.topModels.prefix(3).enumerated()), id: \.offset) { _, m in
                    ModelMini(model: m, maxCredits: maxCr)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Widget

struct HiggsfieldWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: CreditsEntry

    var body: some View {
        Group {
            switch family {
            case .systemSmall: SmallView(snapshot: entry.snapshot)
            default: MediumView(snapshot: entry.snapshot)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct HiggsfieldUsageWidget: Widget {
    let kind = "HiggsfieldUsageWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CreditsProvider()) { entry in
            HiggsfieldWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Higgsfield Usage")
        .description("Your Higgsfield credit balance and top model spend at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct HiggsfieldUsageWidgetBundle: WidgetBundle {
    var body: some Widget {
        HiggsfieldUsageWidget()
    }
}
