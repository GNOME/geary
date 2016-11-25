/*
 * Copyright 2016 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * Application logic for ClientWebView and subclasses.
 */

var PageState = function() { };
PageState.prototype = {
    allowRemoteImages: false,
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
    }
};

function emitPreferredHeightChanged() {
    window.webkit.messageHandlers.preferredHeightChanged.postMessage(
        window.document.documentElement.offsetHeight
    );
}

var geary = new PageState();
window.onload = function() {
    emitPreferredHeightChanged();
};
