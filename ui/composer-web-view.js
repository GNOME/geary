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
var ComposerPageState = function() {
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

        var state = this;
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
        var nodeList = document.querySelectorAll(
            "blockquote[style=\"margin: 0 0 0 40px; border: none; padding: 0px;\"]");
        for (var i = 0; i < nodeList.length; ++i) {
            nodeList.item(i).setAttribute(
                "style",
                "margin: 0 0 0 40px; padding: 0px; border:none;"
            );
        }

        // Focus within the HTML document
        document.body.focus();

        // Set cursor at appropriate position
        var cursor = document.getElementById("cursormarker");
        if (cursor != null) {
            var range = document.createRange();
            range.selectNodeContents(cursor);
            range.collapse(false);

            var selection = window.getSelection();
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
        return ComposerPageState.htmlToFlowedText(
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
 * Convert a HTML DOM tree to RFC 3676 format=flowed text.
 *
 * This will modify/reset the DOM.
 */
ComposerPageState.htmlToFlowedText = function(root) {
    var savedDoc = root.innerHTML;
    var blockquotes = root.querySelectorAll("blockquote");
    var nbq = blockquotes.length;
    var bqtexts = new Array(nbq);

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
        console.log("Line: " + text);
        if (text.substr(-1, 1) == "\n") {
            text = text.slice(0, -1);
            console.log("  found expected newline at end of quote!");
        } else {
            console.log(
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

    // Reassemble plain text out of parts, replace non-breaking
    // space with regular space
    var doctext = ComposerPageState.resolveNesting(
        root.innerText, bqtexts
    ).replace("\xc2\xa0", " ");

    // Reassemble DOM
    root.innerHTML = savedDoc;

    // Wrap, space stuff, quote
    var lines = doctext.split("\n");
    flowed = [];
    for (let line of lines) {
        // Strip trailing whitespace, so it doesn't look like a flowed
        // line.  But the signature separator "-- " is special, so
        // leave that alone.
        if (line != "-- ") {
            line = line.trimRight();
        }
        let quoteLevel = 0;
        while (line[quoteLevel] == ComposerPageState.QUOTE_MARKER) {
            quoteLevel += 1;
        }
        line = line.substr(quoteLevel, line.length);
        let prefix = quoteLevel > 0 ? '>'.repeat(quoteLevel) + " " : "";
        let maxLen = 72 - prefix.length;

        do {
            let startInd = 0;
            if (quoteLevel == 0 &&
                (line.startsWith(">") || line.startsWith("From"))) {
                line = " " + line;
                startInd = 1;
            }

            let cutInd = line.length;
            if (cutInd > maxLen) {
                let beg = line.substr(0, maxLen);
                cutInd = beg.lastIndexOf(" ", startInd) + 1;
                if (cutInd == 0) {
                    cutInd = line.indexOf(" ", startInd) + 1;
                    if (cutInd == 0) {
                        cutInd = line.length;
                    }
                    if (cutInd > 998 - prefix.length) {
                        cutInd = 998 - prefix.length;
                    }
                }
            }
            flowed.push(prefix + line.substr(0, cutInd) + "\n");
            line = line.substr(cutInd, line.length);
        } while (line.length > 0);
    }

    return flowed.join("");
};

ComposerPageState.resolveNesting = function(text, values) {
    let tokenregex = new RegExp(
        "(.?)" +
            ComposerPageState.QUOTE_START +
            "([0-9]*)" +
            ComposerPageState.QUOTE_END +
            "(?=(.?))"
    );
    return text.replace(tokenregex, function(match, p1, p2, p3, offset, str) {
        let key = new Number(p2);
        let prevChar = p1;
        let nextChar = p3;
        let insertNext = "";
        // Make sure there's a newline before and after the quote.
        if (prevChar != "" && prevChar != "\n")
            prevChar = prevChar + "\n";
        if (nextChar != "" && nextChar != "\n")
            insertNext = "\n";

        let value = "";
        if (key >= 0 && key < values.length) {
            let nested = ComposerPageState.resolveNesting(values[key], values);
            value = prevChar + ComposerPageState.quoteLines(nested) + insertNext;
        } else {
            console.log("Regex error in denesting blockquotes: Invalid key");
        }
        return value;
    });
};

ComposerPageState.quoteLines = function(text) {
    let lines = text.split("\n");
    for (let i = 0; i < lines.length; i++)
        lines[i] = ComposerPageState.QUOTE_MARKER + lines[i];
    return lines.join("\n");
};


var geary = new ComposerPageState();
window.onload = function() {
    geary.loaded();
};
