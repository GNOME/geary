/*
 * Copyright 2016 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * Application logic for ClientWebView and subclasses.
 */

var PageState = function() {
    this.init.apply(this, arguments);
};
PageState.prototype = {
    init: function() {
        this.allowRemoteImages = false;
        this.loaded = false;

        var state = this;
        var timeoutId = window.setInterval(function() {
            state.preferredHeightChanged();
            if (state.loaded) {
                window.clearTimeout(timeoutId);
            }
        }, 50);
    },
    loadRemoteImages: function() {
        this.allowRemoteImages = true;
        var images = document.getElementsByTagName("IMG");
        for (var i = 0; i < images.length; i++) {
            var img = images.item(i);
            var src = img.src;
            img.src = "";
            img.src = src;
        }
    },
    remoteImageLoadBlocked: function() {
        window.webkit.messageHandlers.remoteImageLoadBlocked.postMessage(null);
    },
    preferredHeightChanged: function() {
        var height = window.document.documentElement.offsetHeight;
        if (height > 0) {
            window.webkit.messageHandlers.preferredHeightChanged.postMessage(
                height
            );
        }
    }
};

var geary = new PageState();
window.onload = function() {
    geary.loaded = true;
};
