import SwiftUI

struct HistoryView: View {
    @State private var items: [ActionHistoryItem] = []
    @State private var filter: HistoryFilter = .all
    @State private var loading = true
    @State private var expanded: Int?

    enum HistoryFilter: String, CaseIterable {
        case all = "All", successful = "Successful", failed = "Failed", today = "Today"
    }

    private var filtered: [ActionHistoryItem] {
        items.filter { item in
            switch filter {
            case .all: return true
            case .successful: return item.status != "error"
            case .failed: return item.status == "error"
            case .today:
                guard let ts = item.timestamp else { return false }
                return Calendar.current.isDateInToday(Date(timeIntervalSince1970: ts))
            }
        }
    }

    var body: some View {
        ZStack {
            LumisColors.background.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                filterChips
                content
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var header: some View {
        HStack {
            Text("History")
                .font(LumisTypography.displayMedium)
                .foregroundStyle(LumisColors.textPrimary)
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 44)
        .padding(.bottom, 8)
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(HistoryFilter.allCases, id: \.self) { f in
                    let active = filter == f
                    Text(f.rawValue)
                        .font(LumisTypography.captionMedium)
                        .foregroundStyle(active ? LumisColors.onTint : LumisColors.textSecondary)
                        .padding(.horizontal, 16)
                        .frame(height: 28)
                        .background(active ? LumisColors.tint : .clear, in: Capsule())
                        .overlay(Capsule().stroke(active ? .clear : LumisColors.divider, lineWidth: 1))
                        .onTapGesture { withAnimation { filter = f }; Haptics.light() }
                }
            }
            .padding(.horizontal, 24)
        }
        .padding(.bottom, 12)
    }

    @ViewBuilder private var content: some View {
        if loading {
            VStack(spacing: 12) {
                ForEach(0..<5, id: \.self) { _ in HistorySkeletonRow() }
            }
            .padding(.horizontal, 20)
            Spacer()
        } else if filtered.isEmpty {
            HistoryEmptyState()
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(filtered) { item in
                        HistoryCard(item: item, isExpanded: expanded == item.id) {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                expanded = expanded == item.id ? nil : item.id
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 100)
            }
        }
    }

    private func load() async {
        loading = items.isEmpty
        defer { loading = false }
        if let fetched = try? await APIClient.history(baseURL: LumisConfig.backendURL) {
            items = fetched
        }
    }
}

private struct HistoryCard: View {
    let item: ActionHistoryItem
    let isExpanded: Bool
    let onTap: () -> Void

    private var type: ActionType { ActionType.from(tool: item.tool_name) }
    private var failed: Bool { item.status == "error" }
    private var action: String { item.title ?? toolMeta(item.tool_name).label }
    private var said: String { item.message ?? "" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(type.tint.opacity(0.18)).frame(width: 40, height: 40)
                    Image(systemName: type.symbol).foregroundStyle(type.tint)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(action)
                        .font(LumisTypography.titleSmall)
                        .foregroundStyle(LumisColors.textPrimary)
                        .lineLimit(1)
                    if !said.isEmpty {
                        Text(said)
                            .font(LumisTypography.bodySmall)
                            .foregroundStyle(LumisColors.textSecondary)
                            .lineLimit(isExpanded ? nil : 1)
                    }
                    Text(RelativeTime.friendly(item.timestamp))
                        .font(LumisTypography.caption)
                        .foregroundStyle(LumisColors.textTertiary)
                }
                Spacer(minLength: 4)
                statusIcon
            }
            .padding(14)

            if isExpanded {
                Divider().overlay(LumisColors.divider)
                VStack(alignment: .leading, spacing: 6) {
                    if !said.isEmpty {
                        Text(said)
                            .font(LumisTypography.bodySmall)
                            .foregroundStyle(LumisColors.textPrimary)
                    }
                    if failed {
                        Text("This action failed.")
                            .font(LumisTypography.caption)
                            .foregroundStyle(LumisColors.destructive)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
            }
        }
        .background(LumisColors.background)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(LumisColors.divider, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(action). \(failed ? "Failed" : "Done"). \(RelativeTime.friendly(item.timestamp))")
    }

    private var statusIcon: some View {
        Group {
            if failed {
                Image(systemName: "xmark").foregroundStyle(LumisColors.destructive)
            } else {
                Image(systemName: "checkmark").foregroundStyle(LumisColors.success)
            }
        }
        .font(.system(size: 14, weight: .semibold))
    }
}

private struct HistoryEmptyState: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            LumisShapeView(state: .idle, containerSize: 80)
            Text("Nothing yet. Try saying \u{201C}Hey Lumis\u{201D} and giving it something to do.")
                .font(.system(size: 14))
                .foregroundStyle(LumisColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 48)
            Spacer()
            Spacer()
        }
    }
}

private struct HistorySkeletonRow: View {
    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(LumisColors.divider).frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4).fill(LumisColors.divider).frame(width: 160, height: 12)
                RoundedRectangle(cornerRadius: 4).fill(LumisColors.divider).frame(width: 100, height: 10)
            }
            Spacer()
        }
        .padding(14)
        .background(LumisColors.background)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(LumisColors.divider, lineWidth: 1))
        .shimmer()
    }
}
