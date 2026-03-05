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

    // ── Links ──

    window.execInsertLink = function(url, text) {
        editor.focus();
        var sel = window.getSelection();
        if (sel.toString().length > 0) {
            // Wrap selection in link
            document.execCommand('createLink', false, url);
        } else if (text) {
            var linkHTML = '<a href="' + url + '">' + text + '</a>&nbsp;';
            document.execCommand('insertHTML', false, linkHTML);
        } else {
            var linkHTML = '<a href="' + url + '">' + url + '</a>&nbsp;';
            document.execCommand('insertHTML', false, linkHTML);
        }
    };

    window.execEditLink = function(oldHref, newHref, newText) {
        var links = editor.querySelectorAll('a[href="' + oldHref + '"]');
        for (var i = 0; i < links.length; i++) {
            var link = links[i];
            // Check if this is the link near the cursor
            if (activeLinkElement && link === activeLinkElement) {
                link.href = newHref;
                if (newText !== undefined && newText !== null) {
                    link.textContent = newText;
                }
                break;
            }
        }
        hideLinkPopover();
        notifyContentChanged();
    };

    window.execUnlink = function() {
        if (activeLinkElement) {
            var text = activeLinkElement.textContent;
            var textNode = document.createTextNode(text);
            activeLinkElement.parentNode.replaceChild(textNode, activeLinkElement);
            activeLinkElement = null;
            hideLinkPopover();
            notifyContentChanged();
        } else {
            document.execCommand('unlink', false, null);
        }
    };

    // ── Link Popover ──

    var activeLinkElement = null;
    var linkPopover = null;

    function createLinkPopover() {
        if (linkPopover) return;
        linkPopover = document.createElement('div');
        linkPopover.id = 'link-popover';
        linkPopover.style.cssText = 'display:none;position:absolute;z-index:999;' +
            'background:var(--bg-color);border:1px solid rgba(128,128,128,0.3);' +
            'border-radius:8px;padding:8px 10px;box-shadow:0 4px 12px rgba(0,0,0,0.15);' +
            'font-size:12px;min-width:200px;max-width:320px;';
        document.body.appendChild(linkPopover);
    }

    function showLinkPopover(linkEl) {
        createLinkPopover();
        activeLinkElement = linkEl;
        var href = linkEl.getAttribute('href') || '';
        var text = linkEl.textContent || '';

        linkPopover.innerHTML =
            '<div style="display:flex;flex-direction:column;gap:6px;">' +
                '<div style="display:flex;align-items:center;gap:6px;">' +
                    '<label style="font-size:11px;color:var(--placeholder-color);min-width:30px;">URL</label>' +
                    '<input id="lp-url" type="text" value="' + href.replace(/"/g, '&quot;') + '" ' +
                        'style="flex:1;background:rgba(128,128,128,0.1);border:1px solid rgba(128,128,128,0.2);' +
                        'border-radius:4px;padding:3px 6px;font-size:12px;color:var(--text-color);outline:none;min-width:0;" />' +
                '</div>' +
                '<div style="display:flex;align-items:center;gap:6px;">' +
                    '<label style="font-size:11px;color:var(--placeholder-color);min-width:30px;">Text</label>' +
                    '<input id="lp-text" type="text" value="' + text.replace(/"/g, '&quot;') + '" ' +
                        'style="flex:1;background:rgba(128,128,128,0.1);border:1px solid rgba(128,128,128,0.2);' +
                        'border-radius:4px;padding:3px 6px;font-size:12px;color:var(--text-color);outline:none;min-width:0;" />' +
                '</div>' +
                '<div style="display:flex;gap:6px;justify-content:flex-end;margin-top:2px;">' +
                    '<button id="lp-remove" style="background:none;border:1px solid rgba(128,128,128,0.3);border-radius:4px;' +
                        'padding:3px 8px;font-size:11px;color:var(--text-color);cursor:pointer;">Remove</button>' +
                    '<button id="lp-open" style="background:none;border:1px solid rgba(128,128,128,0.3);border-radius:4px;' +
                        'padding:3px 8px;font-size:11px;color:var(--text-color);cursor:pointer;">Open</button>' +
                    '<button id="lp-save" style="background:var(--accent-color);border:none;border-radius:4px;' +
                        'padding:3px 10px;font-size:11px;color:#fff;cursor:pointer;font-weight:500;">Save</button>' +
                '</div>' +
            '</div>';

        // Position below the link
        var rect = linkEl.getBoundingClientRect();
        linkPopover.style.display = 'block';
        linkPopover.style.left = Math.max(4, rect.left) + 'px';
        linkPopover.style.top = (rect.bottom + 6) + 'px';

        // Wire buttons
        document.getElementById('lp-save').onclick = function(e) {
            e.preventDefault(); e.stopPropagation();
            var newUrl = document.getElementById('lp-url').value;
            var newText = document.getElementById('lp-text').value;
            if (activeLinkElement) {
                activeLinkElement.href = newUrl;
                activeLinkElement.textContent = newText;
                notifyContentChanged();
            }
            hideLinkPopover();
        };
        document.getElementById('lp-remove').onclick = function(e) {
            e.preventDefault(); e.stopPropagation();
            execUnlink();
        };
        document.getElementById('lp-open').onclick = function(e) {
            e.preventDefault(); e.stopPropagation();
            var url = document.getElementById('lp-url').value;
            if (url) post({ type: 'openLink', url: url });
        };

        // Prevent popover inputs from triggering editor events
        var inputs = linkPopover.querySelectorAll('input');
        for (var i = 0; i < inputs.length; i++) {
            inputs[i].addEventListener('keydown', function(e) { e.stopPropagation(); });
        }
    }

    function hideLinkPopover() {
        if (linkPopover) {
            linkPopover.style.display = 'none';
            activeLinkElement = null;
        }
    }

    window.hideLinkPopover = hideLinkPopover;

    // Click on link → show popover
    editor.addEventListener('click', function(e) {
        var target = e.target;
        if (target.tagName === 'A') {
            e.preventDefault();
            showLinkPopover(target);
        } else if (linkPopover && linkPopover.style.display !== 'none' && !linkPopover.contains(target)) {
            hideLinkPopover();
        }
    });

    // Hide popover when clicking outside
    document.addEventListener('mousedown', function(e) {
        if (linkPopover && linkPopover.style.display !== 'none'
            && !linkPopover.contains(e.target)
            && e.target.tagName !== 'A') {
            hideLinkPopover();
        }
    });

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

        var selectedText = sel.toString();

        post({
            type: 'selectionChanged',
            bold: bold, italic: italic, underline: underline,
            strikethrough: strikethrough, fontSize: fontSize,
            textColor: textColor, alignment: alignment,
            selectedText: selectedText
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

    // ── Keyboard shortcuts ──
    // Intercept formatting shortcuts so they execute in the editor
    // and don't propagate to the app's global shortcut handlers.

    editor.addEventListener('keydown', function(e) {
        var cmd = e.metaKey || e.ctrlKey;
        var shift = e.shiftKey;
        var key = e.key.toLowerCase();

        // — Cmd-based shortcuts —
        if (cmd) {
            switch (key) {
                // Text formatting
                case 'b': // Bold
                    e.preventDefault(); e.stopPropagation();
                    document.execCommand('bold', false, null);
                    return;
                case 'i': // Italic
                    e.preventDefault(); e.stopPropagation();
                    document.execCommand('italic', false, null);
                    return;
                case 'u': // Underline
                    e.preventDefault(); e.stopPropagation();
                    document.execCommand('underline', false, null);
                    return;

                // Undo / Redo
                case 'z':
                    e.preventDefault(); e.stopPropagation();
                    if (shift) {
                        document.execCommand('redo', false, null);
                    } else {
                        document.execCommand('undo', false, null);
                    }
                    return;

                // Select all (within editor only)
                case 'a':
                    e.preventDefault(); e.stopPropagation();
                    var range = document.createRange();
                    range.selectNodeContents(editor);
                    var sel = window.getSelection();
                    sel.removeAllRanges();
                    sel.addRange(range);
                    return;

                // Strikethrough (Cmd+Shift+X)
                case 'x':
                    if (shift) {
                        e.preventDefault(); e.stopPropagation();
                        document.execCommand('strikeThrough', false, null);
                        return;
                    }
                    break;

                // Lists (Cmd+Shift+7 = numbered, Cmd+Shift+8 = bullet)
                case '7':
                    if (shift) {
                        e.preventDefault(); e.stopPropagation();
                        document.execCommand('insertOrderedList', false, null);
                        return;
                    }
                    break;
                case '8':
                    if (shift) {
                        e.preventDefault(); e.stopPropagation();
                        document.execCommand('insertUnorderedList', false, null);
                        return;
                    }
                    break;

                // Alignment (Cmd+Shift+L/E/R/J)
                case 'l':
                    if (shift) {
                        e.preventDefault(); e.stopPropagation();
                        document.execCommand('justifyLeft', false, null);
                        return;
                    }
                    break;
                case 'e':
                    if (shift) {
                        e.preventDefault(); e.stopPropagation();
                        document.execCommand('justifyCenter', false, null);
                        return;
                    }
                    break;
                case 'r':
                    if (shift) {
                        e.preventDefault(); e.stopPropagation();
                        document.execCommand('justifyRight', false, null);
                        return;
                    }
                    break;
                case 'j':
                    if (shift) {
                        e.preventDefault(); e.stopPropagation();
                        document.execCommand('justifyFull', false, null);
                        return;
                    }
                    break;

                // Indent / Outdent (Cmd+] / Cmd+[)
                case ']':
                    e.preventDefault(); e.stopPropagation();
                    document.execCommand('indent', false, null);
                    return;
                case '[':
                    e.preventDefault(); e.stopPropagation();
                    document.execCommand('outdent', false, null);
                    return;

                // Remove formatting (Cmd+\)
                case '\\':
                    e.preventDefault(); e.stopPropagation();
                    document.execCommand('removeFormat', false, null);
                    return;

                // Link insertion (Cmd+K)
                case 'k':
                    e.preventDefault(); e.stopPropagation();
                    var currentSel = window.getSelection();
                    var selectedText = currentSel.toString();
                    var url = prompt('Enter URL:', 'https://');
                    if (url) {
                        if (selectedText) {
                            document.execCommand('createLink', false, url);
                        } else {
                            var linkHTML = '<a href="' + url + '">' + url + '</a>';
                            document.execCommand('insertHTML', false, linkHTML);
                        }
                    }
                    return;
            }
        }

        // — Tab / Shift+Tab for indent/outdent —
        if (e.key === 'Tab') {
            e.preventDefault(); e.stopPropagation();
            if (shift) {
                document.execCommand('outdent', false, null);
            } else {
                document.execCommand('indent', false, null);
            }
            return;
        }

        // — Auto-link URLs on Space/Enter —
        if (e.key === ' ' || e.key === 'Enter') {
            var sel = window.getSelection();
            if (!sel.rangeCount) return;
            var node = sel.focusNode;
            if (node && node.nodeType === 3) {
                var text = node.textContent;
                var match = text.match(/(https?:\/\/[^\s<]+)$/);
                if (match) {
                    var linkUrl = match[1];
                    var offset = text.lastIndexOf(linkUrl);
                    var linkRange = document.createRange();
                    linkRange.setStart(node, offset);
                    linkRange.setEnd(node, offset + linkUrl.length);
                    var link = document.createElement('a');
                    link.href = linkUrl;
                    link.textContent = linkUrl;
                    linkRange.deleteContents();
                    linkRange.insertNode(link);
                    // Move cursor after link
                    linkRange.setStartAfter(link);
                    linkRange.collapse(true);
                    sel.removeAllRanges();
                    sel.addRange(linkRange);
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
