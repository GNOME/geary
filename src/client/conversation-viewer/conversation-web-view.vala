/* 
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2016 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class ConversationWebView : ClientWebView {

    private const string USER_CSS = "user-message.css";

    private static WebKit.UserStyleSheet? user_stylesheet = null;
    private static WebKit.UserStyleSheet? app_stylesheet = null;
    private static WebKit.UserScript? app_script = null;

    public static void load_resources(GearyApplication app)
        throws Error {
        ConversationWebView.app_script =
            ClientWebView.load_app_script(app, "conversation-web-view.js");
        ConversationWebView.app_stylesheet =
            ClientWebView.load_app_stylesheet(app, "conversation-web-view.css");
        ConversationWebView.user_stylesheet =
            ClientWebView.load_user_stylesheet(app, "user-message.css");
    }


    public ConversationWebView() {
        base();
        this.user_content_manager.add_script(ConversationWebView.app_script);
        this.user_content_manager.add_style_sheet(ConversationWebView.app_stylesheet);
        if (ConversationWebView.user_stylesheet != null) {
            this.user_content_manager.add_style_sheet(ConversationWebView.user_stylesheet);
        }
    }

    /**
     * Returns the current selection, for prefill as find text.
     */
    public async string get_selection_for_find() throws Error{
        WebKit.JavascriptResult result = yield this.run_javascript("geary.getSelectionForFind();", null);
        return get_string_result(result);
    }

    /**
     * Returns the current selection, for quoting in a message.
     */
    public async string get_selection_for_quoting() throws Error {
        WebKit.JavascriptResult result = yield this.run_javascript("geary.getSelectionForQuoting();", null);
        return get_string_result(result);
    }

}
