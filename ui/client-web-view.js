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
        this.hasSelection = false;
        this.lastPreferredHeight = 0;

        let state = this;

        // Coalesce multiple calls to updatePreferredHeight using a
        // timeout to avoid the overhead of multiple JS messages sent
        // to the app and hence view multiple resizes being queued.
        let queueTimeout = null;
        let queuePreferredHeightUpdate = function() {
            if (queueTimeout != null) {
                clearTimeout(queueTimeout);
            }
            queueTimeout = setTimeout(
                function() { state.updatePreferredHeight(); }, 10
            );
        };

        // Queues an update after the DOM has been initially loaded
        // and had any changes made to it by derived classes.
        document.addEventListener("DOMContentLoaded", function(e) {
            state.loaded();
            queuePreferredHeightUpdate();
        });

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
        // user resized the window
        window.addEventListener("resize", function(e) {
            queuePreferredHeightUpdate();
        }, false); // load does not bubble

        // Queues an update when a transition has completed, e.g. if the
        // user resized the window
        window.addEventListener("transitionend", function(e) {
            queuePreferredHeightUpdate();
        }, false); // load does not bubble
    },
    getPreferredHeight: function() {
        let html = window.document.documentElement;
        let height = html.offsetHeight;
        let computed = window.getComputedStyle(html);
        let top = computed.getPropertyValue('margin-top');
        let bot = computed.getPropertyValue('margin-bottom');

        return (
            height
                + parseInt(top.substring(0, top.length - 2))
                + parseInt(bot.substring(0, bot.length - 2))
        );
    },
    loaded: function() {
        this.isLoaded = true;
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

        let updated = false;
        if (height > 0 && height != this.lastPreferredHeight) {
            updated = true;
            this.lastPreferredHeight = height;
            window.webkit.messageHandlers.preferredHeightChanged.postMessage(
                height
            );
        }
        return updated;
    },
    selectionChanged: function() {
        let hasSelection = !window.getSelection().isCollapsed;
        if (this.hasSelection != hasSelection) {
            this.hasSelection = hasSelection;
            window.webkit.messageHandlers.selectionChanged.postMessage(hasSelection);
        }
    }
};
