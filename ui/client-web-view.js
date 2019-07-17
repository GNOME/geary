/*
 * Copyright 2016 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * Application logic for ClientWebView and subclasses.
 */

let PageState = function() {
    this.init.apply(this, arguments);
};
PageState.prototype = {
    init: function() {
        this.allowRemoteImages = false;
        this.isLoaded = false;
        this.undoEnabled = false;
        this.redoEnabled = false;
        this.hasSelection = false;
        this.lastPreferredHeight = 0;

        let state = this;

        // Set up an observer to keep track of modifications made to
        // the document when editing.
        let modifiedId = null;
        this.bodyObserver = new MutationObserver(function(records) {
            if (modifiedId == null) {
                modifiedId = window.setTimeout(function() {
                    state.documentModified();
                    state.checkCommandStack();
                    modifiedId = null;
                }, 1000);
            }
        });

        document.addEventListener("DOMContentLoaded", function(e) {
            state.loaded();
        });

        // Coalesce multiple calls to updatePreferredHeight using a
        // timeout to avoid the overhead of multiple JS messages sent
        // to the app and hence view multiple resizes being queued.
        let queueTimeout = null;
        let queuePreferredHeightUpdate = function() {
            if (queueTimeout != null) {
                clearTimeout(queueTimeout);
            }
            queueTimeout = setTimeout(
                function() { state.updatePreferredHeight(); }, 100
            );
        };

        // Queues an update when the complete document is loaded.
        //
        // Note also that the delay introduced here by this last call
        // to queuePreferredHeightUpdate when the complete document is
        // loaded seems to be important to get an acurate idea of the
        // final document size.
        window.addEventListener("load", function(e) {
            queuePreferredHeightUpdate();
        }, true); // load does not bubble

        // Queues updates for any STYLE, IMG and other loaded
        // elements, hence handles resizing when the user later
        // requests remote images loading.
        document.addEventListener("load", function(e) {
            queuePreferredHeightUpdate();
        }, true); // load does not bubble

        // Queues an update if the window changes size, e.g. if the
        // user resized the window. Only trigger when the width has
        // changed however since the height should only change as the
        // body is being loaded.
        let width = window.innerWidth;
        window.addEventListener("resize", function(e) {
            let currentWidth = window.innerWidth;
            if (width != currentWidth) {
                width = currentWidth;
                queuePreferredHeightUpdate();
            }
        }, false); // load does not bubble

        // Queues an update when a transition has completed, e.g. if the
        // user resized the window
        window.addEventListener("transitionend", function(e) {
            queuePreferredHeightUpdate();
        }, false); // load does not bubble
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
        // Always fire a prefered height update first so that it will
        // be vaguegly correct when notifying of the HTML load
        // completing.
        this.updatePreferredHeight();
        window.webkit.messageHandlers.contentLoaded.postMessage(null);
    },
    loadRemoteImages: function() {
        this.allowRemoteImages = true;
        let images = document.getElementsByTagName("IMG");
        for (let i = 0; i < images.length; i++) {
            let img = images.item(i);
            let src = img.src;
            img.src = "";
            img.src = src;
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
    remoteImageLoadBlocked: function() {
        window.webkit.messageHandlers.remoteImageLoadBlocked.postMessage(null);
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
            window.webkit.messageHandlers.preferredHeightChanged.postMessage(
                height
            );
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
    documentModified: function(element) {
        window.webkit.messageHandlers.documentModified.postMessage(null);
    },
    selectionChanged: function() {
        let hasSelection = !window.getSelection().isCollapsed;
        if (this.hasSelection != hasSelection) {
            this.hasSelection = hasSelection;
            window.webkit.messageHandlers.selectionChanged.postMessage(hasSelection);
        }
    }
};
