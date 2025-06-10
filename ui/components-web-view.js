/*
 * Copyright © 2016-2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * Application logic for Components.WebView and subclasses.
 */

let PageState = function() {
    this.init.apply(this, arguments);
};
PageState.prototype = {
    init: function() {
        this.isLoaded = false;
        this.undoEnabled = false;
        this.redoEnabled = false;
        this.hasSelection = false;
        this.lastPreferredHeight = 0;

        this._selectionChanged = MessageSender("selection_changed");
        this._contentLoaded = MessageSender("content_loaded");
        this._preferredHeightChanged = MessageSender("preferred_height_changed");
        this._commandStackChanged = MessageSender("command_stack_changed");
        this._documentModified = MessageSender("document_modified");

        // Set up an observer to keep track of modifications made to
        // the document when editing.
        let modifiedId = null;
        this.bodyObserver = new MutationObserver((records) => {
            if (modifiedId == null) {
                modifiedId = window.setTimeout(() => {
                    this.documentModified();
                    this.checkCommandStack();
                    modifiedId = null;
                }, 1000);
            }
        });

        this.heightObserver = new ResizeObserver((entries) => {
            this.updatePreferredHeight();
        });

        document.addEventListener("DOMContentLoaded", (e) => {
            this.heightObserver.observe(window.document.documentElement);
            this.loaded();
        });

        document.addEventListener("selectionchange", (e) => {
            this.selectionChanged();
        });

        this.testResult = null;
    },
    getPreferredHeight: function() {
        // Return the scroll height of the HTML element since the BODY
        // may have margin/border/padding and we want to know
        // precisely how high the widget needs to be to avoid
        // scrolling.
        return window.document.documentElement.scrollHeight;
    },
    getHtml: function() {
        return document.body.innerHTML;
    },
    loaded: function() {
        this.isLoaded = true;
        // Always fire a preferred height update first so that it will
        // be vaguegly correct when notifying of the HTML load
        // completing.
        this.updatePreferredHeight();
        this._contentLoaded();
        if (window.UNSET_HTML_COLORS) {
          document.body.setAttribute("data-geary-theme", "dark");
          DarkReader.auto({
            // Defaults is too dark. These colors are better fitting into Adwaita style.
            darkSchemeBackgroundColor: "#2a2d30",
            darkSchemeTextColor: "#eaeaea",
          });
        }
    },
    loadRemoteResources: function() {
        const TYPES = "*[src], *[srcset]";
        for (const element of document.body.querySelectorAll(TYPES)) {
            let src = "";
            try {
                src = element.src;
            } catch (e) {
                // fine
            }
            if (src != "") {
                element.src = "";
                element.src = src;
            }

            let srcset = "";
            try {
                srcset = element.srcset;
            } catch (e) {
                // fine
            }
            if (srcset != "") {
                element.srcset = "";
                element.srcset = srcset;
            }
        }
    },
    setEditable: function(enabled) {
        if (!enabled) {
            this.stopBodyObserver();
        }
        document.body.contentEditable = enabled;
        if (enabled) {
            // Enable modification observation only after the document
            // has been set editable as WebKit will alter some attrs
            this.startBodyObserver();
        }
    },
    startBodyObserver: function() {
        let config = {
            attributes: true,
            childList: true,
            characterData: true,
            subtree: true
        };
        this.bodyObserver.observe(document.body, config);
    },
    stopBodyObserver: function() {
        this.bodyObserver.disconnect();
    },
    /**
     * Sends "preferredHeightChanged" message if it has changed.
     */
    updatePreferredHeight: function(height) {
        if (height === undefined) {
            height = this.getPreferredHeight();
        }

        // Don't send the message until after the DOM has been fully
        // loaded and processed by any derived classes. Since
        // ConversationPageState may collapse any quotes, sending the
        // current preferred height before then may send a value that
        // is too large, causing the message body view to grow then
        // shrink again, leading to visual flicker.
        if (this.isLoaded && height > 0 && height != this.lastPreferredHeight) {
            this.lastPreferredHeight = height;
            this._preferredHeightChanged(height);
        }
    },
    checkCommandStack: function() {
        let canUndo = document.queryCommandEnabled("undo");
        let canRedo = document.queryCommandEnabled("redo");

        if (canUndo != this.undoEnabled || canRedo != this.redoEnabled) {
            this.undoEnabled = canUndo;
            this.redoEnabled = canRedo;
            this._commandStackChanged(this.undoEnabled, this.redoEnabled);
        }
    },
    documentModified: function(element) {
        this._documentModified();
    },
    selectionChanged: function() {
        let hasSelection = !window.getSelection().isCollapsed;
        if (this.hasSelection != hasSelection) {
            this.hasSelection = hasSelection;
            this._selectionChanged(hasSelection);
        }
    },
    // Methods below are for unit tests.
    testVoid: function() {
        this.testResult = "void";
    },
    testReturn: function(value) {
        this.testResult = value;
        return value;
    },
    testThrow: function(value) {
        this.testResult = value;
        throw this.testResult;
    }
};

let MessageSender = function(name) {
    return function() {
        // Since typeof(arguments) == 'object', convert to an array so
        // that Components.WebView.MessageCallback callbacks get
        // arrays or tuples rather than dicts as arguments
        _GearyWebExtension.send(name, Array.from(arguments));
    };
};
