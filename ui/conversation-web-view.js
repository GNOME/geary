/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2016 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * Application logic for ConversationWebView.
 */
let ConversationPageState = function() {
    this.init.apply(this, arguments);
};

ConversationPageState.QUOTE_CONTAINER_CLASS = "geary-quote-container";
ConversationPageState.QUOTE_HIDE_CLASS = "geary-hide";

ConversationPageState.prototype = {
    __proto__: PageState.prototype,
    init: function() {
        PageState.prototype.init.apply(this, []);
    },
    loaded: function() {
        this.updateDirection();
        this.createControllableQuotes();
        this.wrapSignature();
        // Chain up here so we continue to a preferred size update
        // after munging the HTML above.
        PageState.prototype.loaded.apply(this, []);
    },
    /**
     * Set dir="auto" if not already set.
     *
     * This should provide a slightly better RTL experience.
     */
    updateDirection: function() {
        let dir = document.documentElement.dir;
        if (dir == null || dir.trim() == "") {
            document.documentElement.dir = "auto";
        }
    },
    /**
     * Starts looking for changes to the page's height.
     */
    updatePreferredHeight: function() {
        let height = this.getPreferredHeight();
        let state = this;
        let timeoutId = window.setInterval(function() {
            let newHeight = state.getPreferredHeight();
            if (height != newHeight) {
                state.preferredHeightChanged();
                window.clearTimeout(timeoutId);
            }
        }, 50);
    },
    /**
     * Add top level blockquotes to hide/show container.
     */
    createControllableQuotes: function() {
        let blockquoteList = document.documentElement.querySelectorAll("blockquote");
        for (let i = 0; i < blockquoteList.length; ++i) {
            let blockquote = blockquoteList.item(i);
            let nextSibling = blockquote.nextSibling;
            let parent = blockquote.parentNode;

            // Only insert into a quote container if the element is a
            // top level blockquote
            if (!ConversationPageState.isDescendantOf(blockquote, "BLOCKQUOTE")) {
                let quoteContainer = document.createElement("DIV");
                quoteContainer.classList.add(
                    ConversationPageState.QUOTE_CONTAINER_CLASS
                );

                // Only make it controllable if the quote is tall enough
                if (blockquote.offsetHeight > 120) {
                    quoteContainer.classList.add("geary-controllable");
                    quoteContainer.classList.add(
                        ConversationPageState.QUOTE_HIDE_CLASS
                    );
                }

                let script = this;
                function newControllerButton(styleClass, text) {
                    let button = document.createElement("BUTTON");
                    button.classList.add("geary-button");
                    button.type = "button";
                    button.onclick = function() {
                        quoteContainer.classList.toggle(
                            ConversationPageState.QUOTE_HIDE_CLASS
                        );
                        script.updatePreferredHeight();
                    };
                    button.appendChild(document.createTextNode(text));

                    let container = document.createElement("DIV");
                    container.classList.add(styleClass);
                    container.appendChild(button);

                    return container;
                }

                quoteContainer.appendChild(newControllerButton(
                    "geary-shower", "▼        ▼        ▼"
                ));
                quoteContainer.appendChild(newControllerButton(
                    "geary-hider", "▲        ▲        ▲"
                ));

                let quoteDiv = document.createElement("DIV");
                quoteDiv.classList.add("geary-quote");
                quoteDiv.appendChild(blockquote);

                quoteContainer.appendChild(quoteDiv);
                parent.insertBefore(quoteContainer, nextSibling);

                this.updatePreferredHeight();
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
        let possibleSigs = document.documentElement.querySelectorAll("div,span,p");
        let i = 0;
        let sigRegex = new RegExp("^--\\s*$");
        let alternateSigRegex = new RegExp("^--\\s*(?:<br|\\R)");
        for (; i < possibleSigs.length; ++i) {
            // Get the div and check that it starts a signature block
            // and is not inside a quote.
            let div = possibleSigs.item(i);
            let innerHTML = div.innerHTML;
            if ((sigRegex.test(innerHTML) || alternateSigRegex.test(innerHTML)) &&
                !ConversationPageState.isDescendantOf(div, "BLOCKQUOTE")) {
                break;
            }
        }
        // If we have a signature, move it and all of its following
        // siblings that are not quotes inside a signature div.
        if (i < possibleSigs.length) {
            let elem = possibleSigs.item(i);
            let parent = elem.parentNode;
            let signatureContainer = document.createElement("DIV");
            signatureContainer.classList.add("geary-signature");
            do {
                // Get its sibling _before_ we move it into the signature div.
                let sibling = elem.nextSibling;
                signatureContainer.appendChild(elem);
                elem = sibling;
            } while (elem != null);
            parent.appendChild(signatureContainer);
        }
    },
    getSelectionForQuoting: function() {
        let quote = null;
        let selection = window.getSelection();
        if (!selection.isCollapsed) {
            let range = selection.getRangeAt(0);
            let ancestor = range.commonAncestorContainer;
            if (ancestor.nodeType != Node.ELEMENT_NODE) {
                ancestor = ancestor.parentNode;
            }

            // If the selection is part of a plain text message,
            // we have to stick it in an appropriately styled div,
            // so that new lines are preserved.
            let dummy = document.createElement("DIV");
            let includeDummy = false;
            if (ConversationPageState.isDescendantOf(ancestor, ".plaintext")) {
                dummy.classList.add("plaintext");
                dummy.setAttribute("style", "white-space: pre-wrap;");
                includeDummy = true;
            }
            dummy.appendChild(range.cloneContents());

            // Remove the chrome we put around quotes, leaving
            // only the blockquote element.
            let quotes = dummy.querySelectorAll(
                "." + ConversationPageState.QUOTE_CONTAINER_CLASS
            );
            for (let i = 0; i < quotes.length; i++) {
                let div = quotes.item(i);
                let blockquote = div.querySelector("blockquote");
                div.parentNode.replaceChild(blockquote, div);
            }

            quote = includeDummy ? dummy.outerHTML : dummy.innerHTML;
        }
        return quote;
    },
    getSelectionForFind: function() {
        let value = null;
        let selection = window.getSelection();

        if (selection.rangeCount > 0) {
            let range = selection.getRangeAt(0);
            value = range.toString().trim();
            if (value == "") {
                value = null;
            }
        }
        return value;
    }
};

ConversationPageState.isDescendantOf = function(node, ancestorTag) {
    let ancestor = node.parentNode;
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
