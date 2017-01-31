/*
 * Copyright 2016 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * Application logic for ConversationWebView.
 */
var ConversationPageState = function() {
    this.init.apply(this, arguments);
};
ConversationPageState.prototype = {
    __proto__: PageState.prototype,
    init: function() {
        PageState.prototype.init.apply(this, []);
    },
    loaded: function() {
        this.updateDirection();
        this.createControllableQuotes();
        this.wrapSignature();
        // Call after so we continue to a preferred size update after
        // munging the HTML above.
        PageState.prototype.loaded.apply(this, []);
    },
    /**
     * Set dir="auto" if not already set.
     *
     * This should provide a slightly better RTL experience.
     */
    updateDirection: function() {
        var dir = document.documentElement.dir;
        if (dir == null || dir.trim() == "") {
            document.documentElement.dir = "auto";
        }
    },
    /**
     * Add top level blockquotes to hide/show container.
     */
    createControllableQuotes: function() {
        var blockquoteList = document.documentElement.querySelectorAll("blockquote");
        for (var i = 0; i < blockquoteList.length; ++i) {
            var blockquote = blockquoteList.item(i);
            var nextSibling = blockquote.nextSibling;
            var parent = blockquote.parentNode;

            // Only insert into a quote container if the element is a
            // top level blockquote
            if (!ConversationPageState.isDescendantOf(blockquote, "BLOCKQUOTE")) {
                var quoteContainer = document.createElement("DIV");
                quoteContainer.classList.add("geary-quote-container");

                // Only make it controllable if the quote is tall enough
                if (blockquote.offsetHeight > 50) {
                    quoteContainer.classList.add("geary-controllable");
                    quoteContainer.classList.add("geary-hide");
                }
                // New lines are preserved within blockquotes, so this
                // string needs to be new-line free.
                quoteContainer.innerHTML =
                    "<div class=\"geary-shower\">" +
                    "<input type=\"button\" value=\"▼        ▼        ▼\" />" +
                    "</div>" +
                    "<div class=\"geary-hider\">" +
                    "<input type=\"button\" value=\"▲        ▲        ▲\" />" +
                    "</div>";

                var quoteDiv = document.createElement("DIV");
                quoteDiv.classList.add("geary-quote");
                quoteDiv.appendChild(blockquote);

                quoteContainer.appendChild(quoteDiv);
                parent.insertBefore(quoteContainer, nextSibling);
            }
        }
    },
    /**
     * Look for and wrap a signature.
     *
     * Most HTML signatures fall into one
     * of these designs which are handled by this method:
     *
     * 1. GMail:            <div>-- </div>$SIGNATURE
     * 2. GMail Alternate:  <div><span>-- </span></div>$SIGNATURE
     * 3. Thunderbird:      <div>-- <br>$SIGNATURE</div>
     *
     */
    wrapSignature: function() {
        var possibleSigs = document.documentElement.querySelectorAll("div,span,p");
        var i = 0;
        var sigRegex = new RegExp("^--\\s*$");
        var alternateSigRegex = new RegExp("^--\\s*(?:<br|\\R)");
        for (; i < possibleSigs.length; ++i) {
            // Get the div and check that it starts a signature block
            // and is not inside a quote.
            var div = possibleSigs.item(i);
            var innerHTML = div.innerHTML;
            if ((sigRegex.test(innerHTML) || alternateSigRegex.test(innerHTML)) &&
                !ConversationPageState.isDescendantOf(div, "BLOCKQUOTE")) {
                break;
            }
        }
        // If we have a signature, move it and all of its following
        // siblings that are not quotes inside a signature div.
        if (i < possibleSigs.length) {
            var elem = possibleSigs.item(i);
            var parent = elem.parentNode;
            var signatureContainer = document.createElement("DIV");
            signatureContainer.classList.add("geary-signature");
            do {
                // Get its sibling _before_ we move it into the signature div.
                var sibling = elem.nextSibling;
                signatureContainer.appendChild(elem);
                elem = sibling;
            } while (elem != null);
            parent.appendChild(signatureContainer);
        }
    }
};

ConversationPageState.isDescendantOf = function(node, ancestorTag) {
    var ancestor = node.parentNode;
    while (ancestor != null) {
        if (ancestor.tagName == ancestorTag) {
            return true;
        }
        ancestor = ancestor.parentNode;
    }
    return false;
};

var geary = new ConversationPageState();
window.onload = function() {
    geary.loaded();
};
