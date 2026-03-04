// editor.js — WKWebView contenteditable JS bridge
// Communicates with Swift via window.webkit.messageHandlers.editor.postMessage()

(function() {
    'use strict';

    var editor = document.getElementById('editor');
    var contentTimer = null;
    var selectionTimer = null;

    // ── Formatting (called from Swift via evaluateJavaScript) ──

    window.execBold = function() { document.execCommand('bold', false, null); };
    window.execItalic = function() { document.execCommand('italic', false, null); };
    window.execUnderline = function() { document.execCommand('underline', false, null); };
    window.execStrikethrough = function() { document.execCommand('strikeThrough', false, null); };
    window.execFontSize = function(px) {
        // execCommand fontSize uses 1-7 scale; use inline style instead
        document.execCommand('fontSize', false, '7');
        var fontElements = editor.querySelectorAll('font[size="7"]');
        for (var i = 0; i < fontElements.length; i++) {
            fontElements[i].removeAttribute('size');
            fontElements[i].style.fontSize = px + 'px';
        }
    };
    window.execForeColor = function(hex) { document.execCommand('foreColor', false, hex); };
    window.execRemoveFormat = function() { document.execCommand('removeFormat', false, null); };

    window.execInsertOrderedList = function() { document.execCommand('insertOrderedList', false, null); };
    window.execInsertUnorderedList = function() { document.execCommand('insertUnorderedList', false, null); };
    window.execAlign = function(dir) { document.execCommand('justify' + dir.charAt(0).toUpperCase() + dir.slice(1), false, null); };
    window.execIndent = function() { document.execCommand('indent', false, null); };
    window.execOutdent = function() { document.execCommand('outdent', false, null); };

    // ── Insertion ──

    window.insertHTML = function(html) {
        editor.focus();
        document.execCommand('insertHTML', false, html);
    };

    window.insertImageBase64 = function(dataURL, cid) {
        editor.focus();
        var imgTag = '<img src="' + dataURL + '" data-cid="' + cid + '" style="max-width:100%;">';
        document.execCommand('insertHTML', false, imgTag);
    };

    // ── Content ──

    window.getHTML = function() { return editor.innerHTML; };
    window.setHTML = function(html) {
        editor.innerHTML = html;
        notifyContentChanged();
    };
    window.focusEditor = function() {
        editor.focus();
        // Place cursor at end
        var range = document.createRange();
        range.selectNodeContents(editor);
        range.collapse(false);
        var sel = window.getSelection();
        sel.removeAllRanges();
        sel.addRange(range);
    };

    // ── Theme ──

    window.setThemeColors = function(textColor, bgColor, accentColor, placeholderColor) {
        document.documentElement.style.setProperty('--text-color', textColor);
        document.documentElement.style.setProperty('--bg-color', bgColor);
        document.documentElement.style.setProperty('--accent-color', accentColor);
        document.documentElement.style.setProperty('--placeholder-color', placeholderColor);
    };

    // ── Helpers ──

    function post(msg) {
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.editor) {
            window.webkit.messageHandlers.editor.postMessage(msg);
        }
    }

    function notifyContentChanged() {
        var html = editor.innerHTML;
        var isEmpty = !editor.textContent.trim() && !editor.querySelector('img');
        post({ type: 'contentChanged', html: html, isEmpty: isEmpty });
    }

    function notifySelectionChanged() {
        var bold = document.queryCommandState('bold');
        var italic = document.queryCommandState('italic');
        var underline = document.queryCommandState('underline');
        var strikethrough = document.queryCommandState('strikeThrough');
        var fontSize = 13;
        var textColor = '#000000';
        var alignment = 'left';

        // Font size detection
        var sel = window.getSelection();
        if (sel.rangeCount > 0) {
            var node = sel.focusNode;
            if (node && node.nodeType === 3) node = node.parentElement;
            if (node) {
                var computed = window.getComputedStyle(node);
                fontSize = Math.round(parseFloat(computed.fontSize));
                textColor = rgbToHex(computed.color);
                var ta = computed.textAlign;
                if (ta === 'start' || ta === 'left') alignment = 'left';
                else if (ta === 'center') alignment = 'center';
                else if (ta === 'right' || ta === 'end') alignment = 'right';
                else if (ta === 'justify') alignment = 'justify';
            }
        }

        post({
            type: 'selectionChanged',
            bold: bold, italic: italic, underline: underline,
            strikethrough: strikethrough, fontSize: fontSize,
            textColor: textColor, alignment: alignment
        });
    }

    function rgbToHex(rgb) {
        if (!rgb || rgb.indexOf('rgb') === -1) return rgb || '#000000';
        var parts = rgb.match(/\d+/g);
        if (!parts || parts.length < 3) return '#000000';
        var r = parseInt(parts[0]), g = parseInt(parts[1]), b = parseInt(parts[2]);
        return '#' + ((1 << 24) + (r << 16) + (g << 8) + b).toString(16).slice(1).toUpperCase();
    }

    // ── Events ──

    editor.addEventListener('input', function() {
        clearTimeout(contentTimer);
        contentTimer = setTimeout(notifyContentChanged, 150);
    });

    document.addEventListener('selectionchange', function() {
        clearTimeout(selectionTimer);
        selectionTimer = setTimeout(notifySelectionChanged, 50);
    });

    // Paste handler — strip Office/Word junk
    editor.addEventListener('paste', function(e) {
        var html = e.clipboardData.getData('text/html');
        if (html) {
            e.preventDefault();
            // Remove class, id, data-* attributes and mso-* styles
            html = html.replace(/\s(class|id|data-[\w-]+)="[^"]*"/gi, '');
            html = html.replace(/mso-[^;:"]+:[^;"]*(;|")/gi, function(m) {
                return m.charAt(m.length - 1) === '"' ? '"' : '';
            });
            // Remove <style> blocks
            html = html.replace(/<style[^>]*>[\s\S]*?<\/style>/gi, '');
            // Remove comments
            html = html.replace(/<!--[\s\S]*?-->/g, '');
            document.execCommand('insertHTML', false, html);
        }
    });

    // Drop handler for files
    editor.addEventListener('drop', function(e) {
        var files = e.dataTransfer.files;
        if (files.length === 0) return;
        e.preventDefault();
        e.stopPropagation();
        for (var i = 0; i < files.length; i++) {
            var file = files[i];
            if (file.type.indexOf('image/') === 0) {
                (function(f) {
                    var reader = new FileReader();
                    reader.onload = function(ev) {
                        post({
                            type: 'imageDropped',
                            data: ev.target.result,
                            mimeType: f.type,
                            filename: f.name
                        });
                    };
                    reader.readAsDataURL(f);
                })(file);
            } else {
                post({
                    type: 'fileDropped',
                    mimeType: file.type,
                    filename: file.name
                });
            }
        }
    });

    editor.addEventListener('dragover', function(e) {
        e.preventDefault();
    });

    // Auto-link URLs on input
    var linkRegex = /(?:^|\s)(https?:\/\/[^\s<]+)/g;
    editor.addEventListener('keydown', function(e) {
        if (e.key === ' ' || e.key === 'Enter') {
            var sel = window.getSelection();
            if (!sel.rangeCount) return;
            var node = sel.focusNode;
            if (node && node.nodeType === 3) {
                var text = node.textContent;
                var match = text.match(/(https?:\/\/[^\s<]+)$/);
                if (match) {
                    var url = match[1];
                    var offset = text.lastIndexOf(url);
                    var range = document.createRange();
                    range.setStart(node, offset);
                    range.setEnd(node, offset + url.length);
                    var link = document.createElement('a');
                    link.href = url;
                    link.textContent = url;
                    range.deleteContents();
                    range.insertNode(link);
                    // Move cursor after link
                    range.setStartAfter(link);
                    range.collapse(true);
                    sel.removeAllRanges();
                    sel.addRange(range);
                }
            }
        }
    });

    // Initial state notification
    setTimeout(function() {
        notifyContentChanged();
        notifySelectionChanged();
    }, 100);
})();
