import Foundation

enum HTMLTemplate {

    static func editorHTML(
        textColor: String,
        backgroundColor: String,
        accentColor: String,
        placeholderColor: String,
        placeholderText: String,
        fontSize: Int = 13,
        initialHTML: String = ""
    ) -> String {
        let jsSource: String
        if let url = Bundle.main.url(forResource: "editor", withExtension: "js"),
           let js = try? String(contentsOf: url, encoding: .utf8) {
            jsSource = js
        } else {
            jsSource = "// editor.js not found"
        }

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        :root {
            --text-color: \(textColor);
            --bg-color: \(backgroundColor);
            --accent-color: \(accentColor);
            --placeholder-color: \(placeholderColor);
        }
        html, body {
            margin: 0;
            padding: 0;
            height: 100%;
            background: var(--bg-color);
            color: var(--text-color);
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Arial, sans-serif;
            font-size: \(fontSize)px;
            line-height: 1.5;
            -webkit-font-smoothing: antialiased;
        }
        #editor {
            min-height: 100%;
            outline: none;
            padding: 8px 4px;
            word-wrap: break-word;
            overflow-wrap: break-word;
        }
        #editor:empty::before {
            content: attr(data-placeholder);
            color: var(--placeholder-color);
            pointer-events: none;
        }
        #editor a {
            color: var(--accent-color);
        }
        #editor blockquote {
            border-left: 3px solid var(--placeholder-color);
            margin: 8px 0;
            padding: 4px 12px;
            color: var(--placeholder-color);
        }
        #editor pre, #editor code {
            font-family: 'SF Mono', Menlo, monospace;
            font-size: 12px;
            background: rgba(128, 128, 128, 0.1);
            padding: 2px 4px;
            border-radius: 3px;
        }
        #editor img {
            max-width: 100%;
            height: auto;
        }
        #editor .serif-signature {
            color: var(--placeholder-color);
        }
        </style>
        </head>
        <body>
        <div id="editor" contenteditable="true" data-placeholder="\(placeholderText.replacingOccurrences(of: "\"", with: "&quot;"))">\(initialHTML)</div>
        <script>
        \(jsSource)
        </script>
        </body>
        </html>
        """
    }
}
