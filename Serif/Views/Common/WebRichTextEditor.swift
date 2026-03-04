import SwiftUI

struct WebRichTextEditor: View {
    @ObservedObject var state: WebRichTextEditorState
    @Binding var htmlContent: String
    var placeholder: String = ""
    var autoFocus: Bool = false
    var onFileDrop: ((URL) -> Void)? = nil
    @Environment(\.theme) private var theme

    var body: some View {
        WebRichTextEditorRepresentable(
            state: state,
            htmlContent: $htmlContent,
            theme: theme,
            placeholder: placeholder,
            autoFocus: autoFocus,
            onFileDrop: onFileDrop
        )
    }
}
