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
        return document.getElementById(ComposerPageState.BODY_ID).innerText;
    },
    setRichText: function(enabled) {
        if (enabled) {
            document.body.classList.remove("plain");
        } else {
            document.body.classList.add("plain");
        }
    },
    linkClicked: function(element) {
        window.getSelection().selectAllChildren(element);
    }
};

var geary = new ComposerPageState();
window.onload = function() {
    geary.loaded();
};
