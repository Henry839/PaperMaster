import SwiftUI

struct PaperListRow: View {
    let paper: Paper
    let screen: AppScreen

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(paper.title)
                        .font(.headline)
                        .lineLimit(2)
                    Text(paper.authorsDisplayText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 6) {
                    StatusChip(status: paper.status)
                    if let dueDate = paper.dueDate, paper.status.isActiveQueue {
                        Text(dueDateLabel(for: dueDate))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack(spacing: 8) {
                if screen == .queue {
                    Text("#\(paper.queuePosition + 1)")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary)
                        .clipShape(Capsule())
                }

                ForEach(Array(paper.tagNames.prefix(3)), id: \.self) { tag in
                    TagChip(name: tag)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func dueDateLabel(for date: Date) -> String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let dueDay = calendar.startOfDay(for: date)
        if dueDay < today {
            return "Overdue · \(date.formatted(date: .abbreviated, time: .omitted))"
        }
        if dueDay == today {
            return "Due today"
        }
        return "Due \(date.formatted(date: .abbreviated, time: .omitted))"
    }
}

private struct StatusChip: View {
    let status: PaperStatus

    var body: some View {
        Text(status.title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(backgroundColor)
            .clipShape(Capsule())
    }

    private var foregroundColor: Color {
        switch status {
        case .inbox:
            .orange
        case .scheduled:
            .blue
        case .reading:
            .mint
        case .done:
            .green
        case .archived:
            .secondary
        }
    }

    private var backgroundColor: Color {
        foregroundColor.opacity(0.14)
    }
}
