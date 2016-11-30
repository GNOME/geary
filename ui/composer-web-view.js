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
ComposerPageState.prototype = {
    __proto__: PageState.prototype,
    init: function() {
        PageState.prototype.init.apply(this, []);
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

        //Util.DOM.bind_event(view, "a", "click", (Callback) on_link_clicked, this);
    }
    // private static void on_link_clicked(WebKit.DOM.Element element, WebKit.DOM.Event event,
    //     ComposerWidget composer) {
    //     try {
    //         composer.editor.get_dom_document().get_default_view().get_selection().
    //             select_all_children(element);
    //     } catch (Error e) {
    //         debug("Error selecting link: %s", e.message);
    //     }
    // }
};

var geary = new ComposerPageState();
window.onload = function() {
    geary.loaded();
};
