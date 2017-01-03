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

        let state = this;
        document.addEventListener("click", function(e) {
            if (e.target.tagName == "A") {
                state.linkClicked(e.target);
            }
        }, true);
    },
    loaded: function() {
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

        // Set cursor at appropriate position
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

        // Chain up here so we continue to a preferred size update
        // after munging the HTML above.
        PageState.prototype.loaded.apply(this, []);
    },
    getHtml: function() {
        return document.getElementById(ComposerPageState.BODY_ID).innerHTML;
    },
    getText: function() {
        return ComposerPageState.htmlToQuotedText(
            document.getElementById(ComposerPageState.BODY_ID)
        );
    },
    setRichText: function(enabled) {
        if (enabled) {
            document.body.classList.remove("plain");
        } else {
            document.body.classList.add("plain");
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
    linkClicked: function(element) {
        window.getSelection().selectAllChildren(element);
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


var geary = new ComposerPageState();
window.onload = function() {
    geary.loaded();
};
