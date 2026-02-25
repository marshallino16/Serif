import SwiftUI
import PDFKit
import AppKit

// MARK: - AttachmentPreviewView

struct AttachmentPreviewView: View {
    let data: Data
    let fileName: String
    let fileType: Attachment.FileType
    var onDownload: (() -> Void)?
    var onClose: (() -> Void)?

    @Environment(\.theme) private var theme
    @State private var zoomScale: CGFloat = 1.0

    private var fileExtension: String {
        (fileName as NSString).pathExtension.lowercased()
    }

    var body: some View {
        VStack(spacing: 0) {
            previewToolbar
            Divider().background(theme.divider)
            previewContent
        }
        .background(theme.detailBackground)
    }

    // MARK: - Toolbar

    private var previewToolbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(fileName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(theme.textPrimary)
                    .lineLimit(1)
                Text(fileType.label)
                    .font(.system(size: 11))
                    .foregroundColor(theme.textTertiary)
            }

            Spacer()

            if fileType == .image {
                HStack(spacing: 4) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            zoomScale = max(0.25, zoomScale - 0.25)
                        }
                    } label: {
                        Image(systemName: "minus.magnifyingglass")
                            .font(.system(size: 13))
                            .foregroundColor(theme.textSecondary)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Zoom out")

                    Text("\(Int(zoomScale * 100))%")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(theme.textTertiary)
                        .frame(minWidth: 36)

                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            zoomScale = min(4.0, zoomScale + 0.25)
                        }
                    } label: {
                        Image(systemName: "plus.magnifyingglass")
                            .font(.system(size: 13))
                            .foregroundColor(theme.textSecondary)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Zoom in")

                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { zoomScale = 1.0 }
                    } label: {
                        Image(systemName: "1.magnifyingglass")
                            .font(.system(size: 13))
                            .foregroundColor(theme.textSecondary)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Reset zoom")

                    Divider().frame(height: 16).padding(.horizontal, 4)
                }
            }

            Button {
                onDownload?()
            } label: {
                Label("Save", systemImage: "arrow.down.circle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(theme.accentPrimary))
            }
            .buttonStyle(.plain)
            .help("Save to disk")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Content router

    @ViewBuilder
    private var previewContent: some View {
        switch fileType {
        case .image:
            imagePreview
        case .pdf:
            pdfPreview
        case .code:
            textPreview
        default:
            unsupportedPreview
        }
    }

    // MARK: - Image

    private var imagePreview: some View {
        GeometryReader { geo in
            ScrollView([.horizontal, .vertical]) {
                if let nsImage = NSImage(data: data) {
                    // Fit the image inside the available viewport at scale 1,
                    // then multiply by zoomScale for user zoom.
                    let natural = nsImage.size
                    let fittedScale = min(
                        (geo.size.width - 48) / max(natural.width, 1),
                        (geo.size.height - 48) / max(natural.height, 1),
                        1.0
                    )
                    let displayW = natural.width  * fittedScale * zoomScale
                    let displayH = natural.height * fittedScale * zoomScale

                    Image(nsImage: nsImage)
                        .resizable()
                        .frame(width: displayW, height: displayH)
                        .padding(24)
                        .animation(.easeInOut(duration: 0.15), value: zoomScale)
                } else {
                    corruptedFileView
                        .frame(width: geo.size.width, height: geo.size.height)
                }
            }
        }
        .background(theme.listBackground)
    }

    // MARK: - PDF

    private var pdfPreview: some View {
        PDFKitView(data: data)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Text / Code

    private var textPreview: some View {
        ScrollView {
            if let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) {
                Text(text)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(theme.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(24)
            } else {
                corruptedFileView
            }
        }
        .background(theme.listBackground)
    }

    // MARK: - Unsupported

    private var unsupportedPreview: some View {
        VStack(spacing: 16) {
            Spacer()

            ZStack {
                Circle()
                    .fill(theme.hoverBackground)
                    .frame(width: 72, height: 72)
                Image(systemName: fileType.rawValue)
                    .font(.system(size: 28))
                    .foregroundColor(theme.textTertiary)
            }

            Text("This file type cannot be previewed")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(theme.textSecondary)

            Text(fileName)
                .font(.system(size: 12))
                .foregroundColor(theme.textTertiary)

            Button {
                onDownload?()
            } label: {
                Label("Download file", systemImage: "arrow.down.circle.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(theme.accentPrimary))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Error state

    private var corruptedFileView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundColor(theme.textTertiary)
            Text("Could not render this file")
                .font(.system(size: 14))
                .foregroundColor(theme.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - PDFKitView (NSViewRepresentable)

private struct PDFKitView: NSViewRepresentable {
    let data: Data

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displaysPageBreaks = true
        view.backgroundColor = .clear
        if let document = PDFDocument(data: data) {
            view.document = document
        }
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        if let document = PDFDocument(data: data), nsView.document == nil {
            nsView.document = document
        }
    }
}

// MARK: - Helpers

extension Attachment.FileType {
    /// True for types we can render inline.
    var isPreviewable: Bool {
        switch self {
        case .image, .pdf, .code: return true
        default: return false
        }
    }
}
