/*
 * Copyright 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A class for editing signatures in the accounts editor.
 */
public class Accounts.SignatureWebView : Components.WebView {


    private static WebKit.UserScript? app_script = null;

    public static new void load_resources()
        throws GLib.Error {
        SignatureWebView.app_script = Components.WebView.load_app_script(
            "signature-web-view.js"
        );
    }


    public SignatureWebView(Application.Configuration config) {
        base(config);
        this.user_content_manager.add_script(SignatureWebView.app_script);
    }

}
