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

        let state = this;
        let timeoutId = window.setInterval(function() {
            state.preferredHeightChanged();
            if (state.isLoaded) {
                window.clearTimeout(timeoutId);
            }
        }, 50);
    },
    getPreferredHeight: function() {
        return window.document.documentElement.offsetHeight;
    },
    loaded: function() {
        this.isLoaded = true;
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
    preferredHeightChanged: function() {
        let height = this.getPreferredHeight();
        if (height > 0) {
            window.webkit.messageHandlers.preferredHeightChanged.postMessage(
                height
            );
        }
    },
    selectionChanged: function() {
        let hasSelection = !window.getSelection().isCollapsed;
        window.webkit.messageHandlers.selectionChanged.postMessage(hasSelection);
    }
};
