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
ComposerPageState.KEYWORD_SPLIT_REGEX = /[\s]+/g;
ComposerPageState.QUOTE_START = "\x91";  // private use one
ComposerPageState.QUOTE_END = "\x92";    // private use two
ComposerPageState.QUOTE_MARKER = "\x7f"; // delete
ComposerPageState.PROTOCOL_REGEX = /^(aim|apt|bitcoin|cvs|ed2k|ftp|file|finger|git|gtalk|http|https|irc|ircs|irc6|lastfm|ldap|ldaps|magnet|news|nntp|rsync|sftp|skype|smb|sms|svn|telnet|tftp|ssh|webcal|xmpp):/i;
// Taken from Geary.HTML.URL_REGEX, without the inline modifier (?x)
// at the start, which is unsupported in JS
ComposerPageState.URL_REGEX = new RegExp("\\b((?:[a-z][\\w-]+:(?:/{1,3}|[a-z0-9%])|www\\d{0,3}[.]|[a-z0-9.\\-]+[.][a-z]{2,4}/)(?:[^\\s()<>]+|\\(([^\\s()<>]+|(\\([^\\s()<>]+\\)))*\\))+(?:\\(([^\\s()<>]+|(\\([^\\s()<>]+\\)))*\\)|[^\\s`!()\\[\\]{};:'\".,<>?«»“”‘’]))", "gi");

ComposerPageState.prototype = {
    __proto__: PageState.prototype,
    init: function() {
        PageState.prototype.init.apply(this, []);
        this.bodyPart = null;
        this.signaturePart = null;
        this.quotePart = null;
        this.focusedPart = null;

        this.selections = new Map();
        this.nextSelectionId = 0;
        this.cursorContext = null;

        let state = this;

        document.addEventListener("click", function(e) {
            if (e.target.tagName == "A") {
                e.preventDefault();
            }
        }, true);
    },
    loaded: function() {
        let state = this;

        this.bodyPart = document.getElementById("geary-body");
        if (this.bodyPart != null) {
            // Capture clicks on the document that aren't on an
            // existing part and prevent focus leaving it. Bug 779369.
            document.addEventListener("mousedown", function(e) {
                if (!state.containedInPart(e.target)) {
                    e.preventDefault();
                    e.stopPropagation();
                }
            });
        } else {
            // This happens if we are loading a draft created by a MUA
            // that isn't Geary, so we can't rely on any of the
            // expected HTML structure to be in place.
            this.bodyPart = document.body;
        }

        this.signaturePart = document.getElementById("geary-signature");
        this.quotePart = document.getElementById("geary-quote");

        // Should be using 'e.key' in listeners below instead of
        // keyIdentifier, but that was only fixed in WK in Oct 2016
        // (WK Bug 36267). Migrate to that when we can rely on it
        // being in WebKitGTK.
        document.body.addEventListener("keydown", function(e) {
            if (e.keyIdentifier == "U+0009" &&// Tab
                !e.ctrlKey && !e.altKey && !e.metaKey) {
                if (!e.shiftKey) {
                    state.tabOut();
                } else {
                    state.tabIn();
                }
                e.preventDefault();
            }
        });
        // We can't use keydown for this, captured or bubbled, since
        // that will also cause the line that the cursor is currenty
        // positioned on when Enter is pressed to also be outdented.
        document.body.addEventListener("keyup", function(e) {
            if (e.keyIdentifier == "Enter" && !e.shiftKey) {
                // XXX WebKit seems to support both InsertNewline and
                // InsertNewlineInQuotedContent arguments for
                // execCommand, both of which sound like they would be
                // useful here. After a quick bit of testing neither
                // worked out of the box, so need to investigate
                // further. See:
                // https://github.com/WebKit/webkit/blob/master/Source/WebCore/editing/EditorCommand.cpp
                state.breakBlockquotes();
            }
        }, true);

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
        this.updateFocusClass(this.bodyPart);

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


        // Enable editing only after modifying the body above.
        this.setEditable(true);

        PageState.prototype.loaded.apply(this, []);
    },
    setEditable: function(enabled) {
        if (!enabled) {
            this.stopBodyObserver();
        }
        this.bodyPart.contentEditable = true;
        if (this.signaturePart != null) {
            this.signaturePart.contentEditable = true;
        }
        if (this.quotePart != null) {
            this.quotePart.contentEditable = true;
        }
        if (enabled) {
            // Enable modification observation only after the document
            // has been set editable as WebKit will alter some attrs
            this.startBodyObserver();
        }
    },
    undo: function() {
        document.execCommand("undo", false, null);
        this.checkCommandStack();
    },
    redo: function() {
        document.execCommand("redo", false, null);
        this.checkCommandStack();
    },
    saveSelection: function() {
        let id = (++this.nextSelectionId).toString();
        this.selections.set(id, SelectionUtil.save());
        return id;
    },
    freeSelection: function(id) {
        this.selections.delete(id);
    },
    insertLink: function(href, selectionId) {
        if (!window.getSelection().isCollapsed) {
            // There is currently a selection, so assume the user
            // knows what they are doing and just linkify it.
            document.execCommand("createLink", false, href);
        } else {
            SelectionUtil.restore(this.selections.get(selectionId));
            document.execCommand("createLink", false, href);
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
    indentLine: function() {
        document.execCommand("indent", false, null);
        let nodeList = document.querySelectorAll(
            "blockquote[style=\"margin: 0 0 0 40px; border: none; padding: 0px;\"]"
        );
        for (let i = 0; i < nodeList.length; ++i) {
            let element = nodeList.item(i);
            element.removeAttribute("style");
            element.setAttribute("type", "cite");
        }
    },
    insertOrderedList: function() {
        document.execCommand("insertOrderedList", false, null);
    },
    insertUnorderedList: function() {
        document.execCommand("insertUnorderedList", false, null);
    },
    updateSignature: function(signature) {
        if (this.signaturePart != null) {
            console.log(signature);
            this.signaturePart.innerHTML = signature;
        }
    },
    deleteQuotedMessage: function() {
        if (this.quotePart != null) {
            this.quotePart.parentNode.removeChild(this.quotePart);
            this.quotePart = null;
        }
    },
    /**
     * Determines if subject or body content refers to attachments.
     */
    containsAttachmentKeyword: function(keywordSpec, subject) {
        let ATTACHMENT_KEYWORDS_SUFFIX = "doc|pdf|xls|ppt|rtf|pps";

        let completeKeys = new Set(keywordSpec.toLocaleLowerCase().split("|"));
        let suffixKeys = new Set(ATTACHMENT_KEYWORDS_SUFFIX.split("|"));

        // Check the subject line
        if (ComposerPageState.containsKeywords(subject, completeKeys, suffixKeys)) {
            return true;
        }

        // Check interesting body text
        let node = this.bodyPart.firstChild;
        let content = [];
        let breakingElements = new Set([
            "BR", "P", "DIV", "BLOCKQUOTE", "TABLE", "OL", "UL", "HR"
        ]);
        while (node != null) {
            if (node.nodeType == Node.TEXT_NODE) {
                content.push(node.textContent);
            } else if (content.nodeType == Node.ELEMENT_NODE) {
                let isBreaking = breakingElements.has(node.nodeName);
                if (isBreaking) {
                    content.push("\n");
                }

                // Only include non-quoted text
                if (content.nodeName != "BLOCKQUOTE") {
                    content.push(content.textContent);
                }
            }
            node = node.nextSibling;
        }
        return ComposerPageState.containsKeywords(
            content.join(""), completeKeys, suffixKeys
        );
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
    breakBlockquotes: function() {
        // Do this in two phases to avoid in-line mutations caused by
        // execCommand affecting the DOM srtcuture
        let count = 0;
        let node = SelectionUtil.getCursorElement();
        while (node != document.body) {
            if (node.nodeName == "BLOCKQUOTE") {
                count++;
            }
            node = node.parentNode;
        }
        while (count > 0) {
            document.execCommand("outdent", false, null);
            count--;
        }
    },
    cleanContent: function() {
        // Prevent any modification signals being sent when mutating
        // the document below.
        this.stopBodyObserver();

        ComposerPageState.cleanPart(this.bodyPart, false);
        ComposerPageState.linkify(this.bodyPart);

        this.signaturePart = ComposerPageState.cleanPart(this.signaturePart, true);
        this.quotePart = ComposerPageState.cleanPart(this.quotePart, true);
    },
    getHtml: function() {
        // Clone the message parts so we can clean them without
        // modifiying the DOM, needed when saving drafts. In contrast
        // with cleanContent above, we don't remove empty elements so
        // they still exist when restoring from draft
        let parent = document.createElement("DIV");
        parent.appendChild(
            ComposerPageState.cleanPart(this.bodyPart.cloneNode(true), false)
        );

        if (this.signaturePart != null) {
            parent.appendChild(
                ComposerPageState.cleanPart(this.signaturePart.cloneNode(true), false)
            );
        }

        if (this.quotePart != null) {
            parent.appendChild(
                ComposerPageState.cleanPart(this.quotePart.cloneNode(true), false)
            );
        }

        return parent.innerHTML;
    },
    getText: function() {
        return ComposerPageState.htmlToQuotedText(document.body);
    },
    setRichText: function(enabled) {
        if (enabled) {
            document.body.classList.remove("plain");
        } else {
            document.body.classList.add("plain");
        }
    },
    selectionChanged: function() {
        PageState.prototype.selectionChanged.apply(this, []);

        let cursor = SelectionUtil.getCursorElement();

        // Update cursor context
        if (cursor != null) {
            let newContext = new EditContext(cursor);
            if (!newContext.equals(this.cursorContext)) {
                this.cursorContext = newContext;
                window.webkit.messageHandlers.cursorContextChanged.postMessage(
                    newContext.encode()
                );
            }
        }

        while (cursor != null) {
            let parent = cursor.parentNode;
            if (parent == document.body) {
                this.updateFocusClass(cursor);
                break;
            }
            cursor = parent;
        }
    },
    /**
     * Work around WebKit note yet supporting :focus-inside pseudoclass.
     */
    updateFocusClass: function(newFocus) {
        if (this.focusedPart != null) {
            this.focusedPart.classList.remove("geary-focus");
            this.focusedPart = null;
        }
        if (newFocus == this.bodyPart ||
            newFocus == this.signaturePart ||
            newFocus == this.quotePart) {
            this.focusedPart = newFocus;
            this.focusedPart.classList.add("geary-focus");
        }
    },
    containedInPart: function(target) {
        let inPart = false;
        for (let part of [this.bodyPart, this.quotePart, this.signaturePart]) {
            if (part != null && (part == target || part.contains(target))) {
                inPart = true;
                break;
            }
        }
        return inPart;
    }
};

/**
 * Determines if any keywords are present in a string.
 */
ComposerPageState.containsKeywords = function(line, completeKeys, suffixKeys) {
    let tokens = new Set(
        line.toLocaleLowerCase().split(ComposerPageState.KEYWORD_SPLIT_REGEX)
    );

    for (let key of completeKeys) {
        if (tokens.has(key)) {
            return true;
        }
    }

    let urlRegex = ComposerPageState.URL_REGEX;
    // XXX assuming all suffixes have length = 3 here.
    let extLen = 3;
    for (let token of tokens) {
        let extDelim = token.length - (extLen + 1);
        // We do care about "a.pdf", but not ".pdf"
        if (token.length >= extLen + 2 && token.charAt(extDelim) == ".") {
            let suffix = token.substring(extDelim + 1);
            if (suffixKeys.has(suffix)) {
                if (token.match(urlRegex) == null) {
                    return true;
                }
            }
        }
    }

    return false;
};

/**
 * Removes internal attributes from a composer part..
 */
ComposerPageState.cleanPart = function(part, removeIfEmpty) {
    if (part != null) {
        part.removeAttribute("class");
        part.removeAttribute("contenteditable");

        if (removeIfEmpty && part.innerText.trim() == "") {
            part.parentNode.removeChild(part);
            part = null;
        }
    }
    return part;
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

// Linkifies "plain text" link
ComposerPageState.linkify = function(node) {
    if (node.nodeType == Node.TEXT_NODE) {
        // Examine text node for something that looks like a URL
        let input = node.nodeValue;
        if (input != null) {
            let output = input.replace(ComposerPageState.URL_REGEX, function(url) {
                if (url.match(ComposerPageState.PROTOCOL_REGEX) != null) {
                    url = "\x01" + url + "\x01";
                }
                return url;
            });

            if (input != output) {
                // We got one!  Now split the text and swap in a new anchor.
                let parent = node.parentNode;
                let sibling = node.nextSibling;
                for (let part of output.split("\x01")) {
                    let newNode = null;
                    if (part.match(ComposerPageState.URL_REGEX) != null) {
                        newNode = document.createElement("A");
                        newNode.href = part;
                        newNode.innerText = part;
                    } else {
                        newNode = document.createTextNode(part);
                    }
                    parent.insertBefore(newNode, sibling);
                }
                parent.removeChild(node);
            }
        }
    } else {
        // Recurse
        let child = node.firstChild;
        while (child != null) {
            // Save the child and get its next sibling early since if
            // it does actually contain a URL, it will be removed from
            // the tree
            let target = child;
            child = child.nextSibling;
            // Don't attempt to linkify existing links
            if (target.nodeName != "A") {
                ComposerPageState.linkify(target);
            }
        }
    }
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
        if (["'", "\""].indexOf(fontFamily.charAt()) != -1) {
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
        if (node != null && node.nodeType != Node.ELEMENT_NODE) {
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
