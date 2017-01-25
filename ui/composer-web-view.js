/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2016 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * Application logic for ComposerWebView.
 */
let ComposerPageState = function() {
    this.init.apply(this, arguments);
};
ComposerPageState.BODY_ID = "message-body";
ComposerPageState.QUOTE_START = "";
ComposerPageState.QUOTE_END = "";
ComposerPageState.QUOTE_MARKER = "\x7f";

ComposerPageState.prototype = {
    __proto__: PageState.prototype,
    init: function() {
        PageState.prototype.init.apply(this, []);

        this.messageBody = null;

        this.undoEnabled = false;
        this.redoEnabled = false;

        this.cursorContext = null;

        let state = this;

        document.addEventListener("click", function(e) {
            if (e.target.tagName == "A") {
                e.preventDefault();
            }
        }, true);

        let modifiedId = null;
        this.bodyObserver = new MutationObserver(function() {
            if (modifiedId == null) {
                modifiedId = window.setTimeout(function() {
                    state.documentModified();
                    state.checkCommandStack();
                    modifiedId = null;
                }, 1000);
            }
        });
    },
    loaded: function() {
        let state = this;

        this.messageBody = document.getElementById(ComposerPageState.BODY_ID);
        this.messageBody.addEventListener("keydown", function(e) {
            // Should be using 'e.key == "Tab"' here, but that was
            // only fixed in WK in Oct 2016 (WK Bug 36267). Migrate to
            // that when we can rely on it being in WebKitGTK.
            if (e.keyIdentifier == "U+0009"
                && !e.ctrlKey
                && !e.altKey
                && !e.metaKey) {
                if (!e.shiftKey) {
                    state.tabOut();
                } else {
                    state.tabIn();
                }
                e.preventDefault();
            }
        });

        // Search for and remove a particular styling when we quote
        // text. If that style exists in the quoted text, we alter it
        // slightly so we don't mess with it later.
        let nodeList = document.querySelectorAll(
            "blockquote[style=\"margin: 0 0 0 40px; border: none; padding: 0px;\"]");
        for (let i = 0; i < nodeList.length; ++i) {
            nodeList.item(i).setAttribute(
                "style",
                "margin: 0 0 0 40px; padding: 0px; border:none;"
            );
        }

        // Focus within the HTML document
        document.body.focus();

        // Set text cursor at appropriate position
        let cursor = document.getElementById("cursormarker");
        if (cursor != null) {
            let range = document.createRange();
            range.selectNodeContents(cursor);
            range.collapse(false);

            let selection = window.getSelection();
            selection.removeAllRanges();
            selection.addRange(range);
            cursor.parentNode.removeChild(cursor);
        }

        // Enable editing and observation machinery only after
        // modifying the body above.
        this.messageBody.contentEditable = true;
        let config = {
            attributes: true,
            childList: true,
            characterData: true,
            subtree: true
        };
        this.bodyObserver.observe(this.messageBody, config);

        // Chain up
        PageState.prototype.loaded.apply(this, []);
    },
    undo: function() {
        document.execCommand("undo", false, null);
        this.checkCommandStack();
    },
    redo: function() {
        document.execCommand("redo", false, null);
        this.checkCommandStack();
    },
    insertLink: function(href) {
        if (!window.getSelection().isCollapsed) {
            // There is currently a selection, so assume the user
            // knows what they are doing and just linkify it.
            document.execCommand("createLink", false, href);
        } else {
            let selected = SelectionUtil.getCursorElement();
            if (selected != null && selected.tagName == "A") {
                // The current cursor element is an A, so select it
                // since createLink requires a range
                let selection = SelectionUtil.save();
                SelectionUtil.selectNode(selected);
                document.execCommand("createLink", false, href);
                SelectionUtil.restore(selection);
            }
        }
    },
    deleteLink: function() {
        if (!window.getSelection().isCollapsed) {
            // There is currently a selection, so assume the user
            // knows what they are doing and just unlink it.
            document.execCommand("unlink", false, null);
        } else {
            let selected = SelectionUtil.getCursorElement();
            if (selected != null && selected.tagName == "A") {
                // The current cursor element is an A, so select it
                // since unlink requires a range
                let selection = SelectionUtil.save();
                SelectionUtil.selectNode(selected);
                document.execCommand("unlink", false, null);
                SelectionUtil.restore(selection);
            }
        }
    },
    updateSignature: function(signature) {
        // XXX need mark the sig somehow so we can find it, select
        // it and replace it using execCommand
    },
    deleteQuotedMessage: function() {
        // XXX need mark the quote somehow so we can find it, select
        // it and delete it using execCommand
    },
    tabOut: function() {
        document.execCommand(
            "inserthtml", false, "<span style='white-space: pre-wrap'>\t</span>"
        );
    },
    tabIn: function() {
        // If there is no selection and the character before the
        // text cursor is tab, delete it.
        let selection = window.getSelection();
        if (selection.isCollapsed) {
            selection.modify("extend", "backward", "character");
            if (selection.getRangeAt(0).toString() == "\t") {
                document.execCommand("delete", false, null);
            } else {
                selection.collapseToEnd();
            }
        }
    },
    getHtml: function() {
        return this.messageBody.innerHTML;
    },
    getText: function() {
        return ComposerPageState.htmlToQuotedText(this.messageBody);
    },
    setRichText: function(enabled) {
        if (enabled) {
            document.body.classList.remove("plain");
        } else {
            document.body.classList.add("plain");
        }
    },
    checkCommandStack: function() {
        let canUndo = document.queryCommandEnabled("undo");
        let canRedo = document.queryCommandEnabled("redo");

        if (canUndo != this.undoEnabled || canRedo != this.redoEnabled) {
            this.undoEnabled = canUndo;
            this.redoEnabled = canRedo;
            window.webkit.messageHandlers.commandStackChanged.postMessage(
                this.undoEnabled + "," + this.redoEnabled
            );
        }
    },
    undoBlockquoteStyle: function() {
        let nodeList = document.querySelectorAll(
            "blockquote[style=\"margin: 0 0 0 40px; border: none; padding: 0px;\"]"
        );
        for (let i = 0; i < nodeList.length; ++i) {
            let element = nodeList.item(i);
            element.removeAttribute("style");
            element.setAttribute("type", "cite");
        }
    },
    documentModified: function(element) {
        window.webkit.messageHandlers.documentModified.postMessage(null);
    },
    selectionChanged: function() {
        PageState.prototype.selectionChanged.apply(this, []);

        let cursor = SelectionUtil.getCursorElement();
        if (cursor != null) {
            let newContext = new EditContext(cursor);
            if (!newContext.equals(this.cursorContext)) {
                this.cursorContext = newContext;
                window.webkit.messageHandlers.cursorContextChanged.postMessage(
                    newContext.encode()
                );
            }
        }
    }
};

/**
 * Convert a HTML DOM tree to plain text with delineated quotes.
 *
 * Lines are delinated using LF. Quoted lines are prefixed with
 * `ComposerPageState.QUOTE_MARKER`, where the number of markers
 * indicates the depth of nesting of the quote.
 *
 * This will modify/reset the DOM, since it ultimately requires
 * stuffing `QUOTE_MARKER` into existing paragraphs and getting it
 * back out in a way that preserves the visual presentation.
 */
ComposerPageState.htmlToQuotedText = function(root) {
    // XXX It would be nice to just clone the root and modify that, or
    // see if we can implement this some other way so as to not modify
    // the DOM at all, but currently unit test show that the results
    // are not the same if we work on a clone, likely because of the
    // use of HTMLElement::innerText. Need to look into it more.

    let savedDoc = root.innerHTML;
    let blockquotes = root.querySelectorAll("blockquote");
    let nbq = blockquotes.length;
    let bqtexts = new Array(nbq);

    // Get text of blockquotes and pull them out of DOM.  They are
    // replaced with tokens deliminated with the characters
    // QUOTE_START and QUOTE_END (from a unicode private use block).
    // We need to get the text while they're still in the DOM to get
    // newlines at appropriate places.  We go through the list of
    // blockquotes from the end so that we get the innermost ones
    // first.
    for (let i = nbq - 1; i >= 0; i--) {
        let bq = blockquotes.item(i);
        let text = bq.innerText;
        if (text.substr(-1, 1) == "\n") {
            text = text.slice(0, -1);
        } else {
            console.debug(
                "  no newline at end of quote: " +
                    text.length > 0
                    ? "0x" + text.codePointAt(text.length - 1).toString(16)
                    : "empty line"
            );
        }
        bqtexts[i] = text;

        bq.innerText = (
            ComposerPageState.QUOTE_START
                + i.toString()
                + ComposerPageState.QUOTE_END
        );
    }

    // Reassemble plain text out of parts, and replace non-breaking
    // space with regular space.
    let text = ComposerPageState.resolveNesting(root.innerText, bqtexts);

    // Reassemble DOM now we have the plain text
    root.innerHTML = savedDoc;

    return ComposerPageState.replaceNonBreakingSpace(text);
};

ComposerPageState.resolveNesting = function(text, values) {
    let tokenregex = new RegExp(
        "(.?)" +
            ComposerPageState.QUOTE_START +
            "([0-9]*)" +
            ComposerPageState.QUOTE_END +
            "(?=(.?))", "g"
    );
    return text.replace(tokenregex, function(match, p1, p2, p3, offset, str) {
        let key = new Number(p2);
        let prevChars = p1;
        let nextChars = p3;
        let insertNext = "";
        // Make sure there's a newline before and after the quote.
        if (prevChars != "" && prevChars != "\n")
            prevChars = prevChars + "\n";
        if (nextChars != "" && nextChars != "\n")
            insertNext = "\n";

        let value = "";
        if (key >= 0 && key < values.length) {
            let nested = ComposerPageState.resolveNesting(values[key], values);
            value = prevChars + ComposerPageState.quoteLines(nested) + insertNext;
        } else {
            console.error("Regex error in denesting blockquotes: Invalid key");
        }
        return value;
    });
};

/**
 * Prefixes each NL-delineated line with `ComposerPageState.QUOTE_MARKER`.
 */
ComposerPageState.quoteLines = function(text) {
    let lines = text.split("\n");
    for (let i = 0; i < lines.length; i++)
        lines[i] = ComposerPageState.QUOTE_MARKER + lines[i];
    return lines.join("\n");
};

/**
 * Converts all non-breaking space chars to plain spaces.
 */
ComposerPageState.replaceNonBreakingSpace = function(text) {
    // XXX this is a separate function for unit testing - since when
    // running as a unit test, HTMLElement.innerText appears to not
    // convert &nbsp into U+00A0.
    return text.replace(new RegExp(" ", "g"), " ");
};


/**
 * Encapsulates editing-related state for a specific DOM node.
 *
 * This must be kept in sync with the vala object of the same name.
 */
let EditContext = function() {
    this.init.apply(this, arguments);
};
EditContext.LINK_MASK = 1 << 0;

EditContext.prototype = {
    init: function(node) {
        this.context = 0;
        this.linkUrl = "";

        if (node.nodeName == "A") {
            this.context |=  EditContext.LINK_MASK;
            this.linkUrl = node.href;
        }

        let styles = window.getComputedStyle(node);
        let fontFamily = styles.getPropertyValue("font-family");
        if (fontFamily.charAt() == "'") {
            fontFamily = fontFamily.substr(1, fontFamily.length - 2);
        }
        this.fontFamily = fontFamily;
        this.fontSize = styles.getPropertyValue("font-size").replace("px", "");
    },
    equals: function(other) {
        return other != null
            && this.context == other.context
            && this.linkUrl == other.linkUrl
            && this.fontFamily == other.fontFamily
            && this.fontSize == other.fontSize;
    },
    encode: function() {
        return [
            this.context.toString(16),
            this.linkUrl,
            this.fontFamily,
            this.fontSize
        ].join(",");
    }
};


/**
 * Utility methods for managing the DOM Selection.
 */
let SelectionUtil = {
    /**
     * Returns the element immediately under the text cursor.
     *
     * If there is a non-empty selection, the element at the end of the
     * selection is returned.
     */
    getCursorElement: function() {
        let selection = window.getSelection();
        let node = selection.focusNode;
        if (node != null && node.nodeType != Node.ELEMENT_TYPE) {
            node = node.parentNode;
        }
        return node;
    },
    /**
     * Modifies the selection so that it contains the given target node.
     */
    selectNode: function(target) {
        let newRange = new Range();
        newRange.selectNode(target);

        let selection = window.getSelection();
        selection.removeAllRanges();
        selection.addRange(newRange);
    },
    /**
     * Saves the current selection so it can be restored with `restore`.
     */
    save: function() {
        let selection = window.getSelection();
        var ranges = [];
        let len = selection.rangeCount;
        for (let i = 0; i < len; ++i) {
            ranges.push(selection.getRangeAt(i));
        }
        return ranges;
    },
    /**
     * Restores the selection saved with `save`.
     */
    restore: function(saved) {
        let selection = window.getSelection();
        selection.removeAllRanges();
        for (let i = 0; i < saved.length; i++) {
            selection.addRange(saved[i]);
        }
    }
};


var geary = new ComposerPageState();
