import SwiftUI

struct AttachmentCardView: View {
    let result: AttachmentSearchResult
    let isSearchActive: Bool
    let accountID: String
    var onTap: (() -> Void)?
    var onAddExclusionRule: ((String) -> Void)?
    var onViewMessage: (() -> Void)?
    @State private var isHovered = false
    @ObservedObject private var thumbCache = ThumbnailCache.shared
    @Environment(\.theme) private var theme

    private let thumbHeight: CGFloat = 80

    // MARK: - Computed

    private var fileType: Attachment.FileType {
        Attachment.FileType(rawValue: result.attachment.fileType) ?? .document
    }

    private var fileTypeIcon: String { fileType.rawValue }

    private var iconBackgroundColor: Color {
        switch fileType {
        case .image:        return .blue.opacity(0.15)
        case .pdf:          return .red.opacity(0.15)
        case .spreadsheet:  return .green.opacity(0.15)
        case .document:     return .indigo.opacity(0.15)
        case .presentation: return .orange.opacity(0.15)
        case .archive:      return .purple.opacity(0.15)
        case .code:         return .teal.opacity(0.15)
        }
    }

    private var iconForegroundColor: Color {
        switch fileType {
        case .image:        return .blue
        case .pdf:          return .red
        case .spreadsheet:  return .green
        case .document:     return .indigo
        case .presentation: return .orange
        case .archive:      return .purple
        case .code:         return .teal
        }
    }

    private var formattedSize: String {
        let size = result.attachment.size
        guard size > 0 else { return "" }
        if size < 1024 { return "\(size) B" }
        if size < 1024 * 1024 { return "\(size / 1024) KB" }
        return String(format: "%.1f MB", Double(size) / (1024 * 1024))
    }

    private var formattedDate: String {
        guard let date = result.attachment.emailDate else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    private var scoreColor: Color {
        if result.score > 0.7 { return .green }
        if result.score > 0.4 { return .orange }
        return .red
    }

    // MARK: - Body

    var body: some View {
        Button {
            onTap?()
        } label: {
            cardContent
        }
        .buttonStyle(.plain)
        .onHover { hovering in isHovered = hovering }
        .onAppear {
            thumbCache.loadIfNeeded(attachment: result.attachment, accountID: accountID)
        }
        .onDisappear {
            thumbCache.cancelIfNeeded(id: result.attachment.id)
        }
        .contextMenu {
            Button {
                onViewMessage?()
            } label: {
                Label("View message", systemImage: "envelope")
            }

            Button {
                onAddExclusionRule?(suggestedPattern)
            } label: {
                Label("Add exclusion rule...", systemImage: "eye.slash")
            }
        }
    }

    /// Suggests a glob pattern from the filename, e.g. "Outlook-abc123.png" → "Outlook-*"
    private var suggestedPattern: String {
        let name = result.attachment.filename
        // Try to find a prefix before a digit-run or random-looking suffix
        if let dashRange = name.range(of: "-"),
           let afterDash = name[dashRange.upperBound...].first,
           afterDash.isNumber || afterDash.isLetter {
            let prefix = String(name[...dashRange.lowerBound])
            return prefix + "*"
        }
        return name
    }

    private var cardContent: some View {
        VStack(spacing: 0) {
            thumbnailArea
            Spacer().frame(height: 10)
            filenameArea
            Spacer().frame(height: 4)
            metadataArea
            if isSearchActive { scoreArea }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .frame(height: 190)
        .background(RoundedRectangle(cornerRadius: 12).fill(theme.detailBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isHovered ? iconForegroundColor.opacity(0.5) : theme.divider, lineWidth: isHovered ? 1.5 : 1)
        )
        .contentShape(Rectangle())
        .scaleEffect(isHovered ? 1.03 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }

    // MARK: - Subviews

    private var thumbnailArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(iconBackgroundColor)

            if let thumb = thumbCache.thumbnail(for: result.attachment.id) {
                GeometryReader { geo in
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                }
            } else {
                VStack(spacing: 4) {
                    Image(systemName: fileTypeIcon)
                        .font(.system(size: 28))
                        .foregroundStyle(iconForegroundColor)
                    if !formattedSize.isEmpty {
                        Text(formattedSize)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(theme.textTertiary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: thumbHeight)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var filenameArea: some View {
        Text(result.attachment.filename)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(theme.textPrimary)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .frame(height: 32, alignment: .top)
    }

    private var metadataArea: some View {
        VStack(spacing: 2) {
            Text(result.attachment.senderName ?? result.attachment.senderEmail ?? "")
                .font(.system(size: 10))
                .foregroundStyle(theme.textSecondary)
                .lineLimit(1)
            Text(formattedDate)
                .font(.system(size: 10))
                .foregroundStyle(theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 28)
    }

    private var scoreArea: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(scoreColor)
                .frame(width: 6, height: 6)
            Text("\(Int(result.score * 100))%")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(theme.textSecondary)
        }
        .frame(height: 14)
    }
}
