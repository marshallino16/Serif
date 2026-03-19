import SwiftUI
import PDFKit

struct iOSAttachmentPreviewView: View {
    let data: Data
    let fileName: String
    let fileType: Attachment.FileType
    var onShare: (() -> Void)?
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var zoomScale: CGFloat = 1.0

    var body: some View {
        NavigationStack {
            previewContent
                .background(theme.detailBackground)
                .navigationTitle(fileName)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        if let onShare {
                            Button {
                                onShare()
                            } label: {
                                Image(systemName: "square.and.arrow.up")
                            }
                        }
                    }
                }
        }
    }

    // MARK: - Content

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
                if let uiImage = UIImage(data: data) {
                    let natural = uiImage.size
                    let fittedScale = min(
                        (geo.size.width - 32) / max(natural.width, 1),
                        (geo.size.height - 32) / max(natural.height, 1),
                        1.0
                    )
                    let displayW = natural.width * fittedScale * zoomScale
                    let displayH = natural.height * fittedScale * zoomScale

                    Image(uiImage: uiImage)
                        .resizable()
                        .frame(width: displayW, height: displayH)
                        .padding(16)
                        .animation(.easeInOut(duration: 0.15), value: zoomScale)
                } else {
                    corruptedView
                        .frame(width: geo.size.width, height: geo.size.height)
                }
            }
        }
        .overlay(alignment: .bottom) {
            zoomControls
                .padding(.bottom, 16)
        }
    }

    private var zoomControls: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation { zoomScale = max(0.25, zoomScale - 0.25) }
            } label: {
                Image(systemName: "minus.magnifyingglass")
                    .font(.system(size: 15))
            }
            Text("\(Int(zoomScale * 100))%")
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .frame(minWidth: 36)
            Button {
                withAnimation { zoomScale = min(4.0, zoomScale + 0.25) }
            } label: {
                Image(systemName: "plus.magnifyingglass")
                    .font(.system(size: 15))
            }
            Button {
                withAnimation { zoomScale = 1.0 }
            } label: {
                Image(systemName: "1.magnifyingglass")
                    .font(.system(size: 15))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .foregroundColor(theme.textPrimary)
    }

    // MARK: - PDF

    private var pdfPreview: some View {
        iOSPDFView(data: data)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Text / Code

    private var textPreview: some View {
        ScrollView {
            if let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) {
                Text(text)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(theme.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            } else {
                corruptedView
            }
        }
    }

    // MARK: - Unsupported

    private var unsupportedPreview: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: fileType.rawValue)
                .font(.system(size: 40))
                .foregroundColor(theme.textTertiary)
            Text("Cannot preview this file type")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(theme.textSecondary)
            Text(fileName)
                .font(.system(size: 13))
                .foregroundColor(theme.textTertiary)
            if let onShare {
                Button { onShare() } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(theme.accentPrimary))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    private var corruptedView: some View {
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

// MARK: - PDF View (UIViewRepresentable)

private struct iOSPDFView: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displaysPageBreaks = true
        view.backgroundColor = .clear
        if let doc = PDFDocument(data: data) {
            view.document = doc
        }
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        if let doc = PDFDocument(data: data) {
            uiView.document = doc
        }
    }
}

// MARK: - FileType Previewable (iOS)

extension Attachment.FileType {
    var isPreviewable: Bool {
        switch self {
        case .image, .pdf, .code: return true
        default: return false
        }
    }
}
