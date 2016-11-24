/*
 * Copyright 2016 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * Application logic for ClientWebView and subclasses.
 */

function emitPreferredHeightChanged() {
    window.webkit.messageHandlers.preferredHeightChanged.postMessage(
        window.document.documentElement.offsetHeight
    );
}

window.onload = function() {
    emitPreferredHeightChanged();
};
