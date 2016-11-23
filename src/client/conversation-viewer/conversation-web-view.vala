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

    public static void load_stylehseets(GearyApplication app)
        throws Error {
        ConversationWebView.app_stylesheet =
            ClientWebView.load_app_stylesheet(app, "conversation-web-view.css");
        ConversationWebView.user_stylesheet =
            ClientWebView.load_user_stylesheet(app, "user-message.css");
    }


    public bool is_height_valid { get; private set; default = false; }


    public ConversationWebView() {
        WebKit.UserContentManager manager = new WebKit.UserContentManager();
        manager.add_style_sheet(ConversationWebView.app_stylesheet);
        if (ConversationWebView.user_stylesheet != null) {
            manager.add_style_sheet(ConversationWebView.user_stylesheet);
        }
        base(manager);
    }

    public bool clean_and_load(string html) {
        // XXX clean me
        load_html(html, null);
        return false; // XXX Work this thes hit out
    }

    public bool has_selection() {
        bool has_selection = false; // XXX set me
        return has_selection;
    }

    /**
     * Returns the current selection, for prefill as find text.
     */
    public string get_selection_for_find() {
        return ""; // XXX
    }

    /**
     * Returns the current selection, for quoting in a message.
     */
    public string get_selection_for_quoting() {
        return ""; // XXX
    }

    /**
     * XXX
     */
    public void unset_controllable_quotes() {
        // XXX
    }

    /**
     * XXX
     */
    public void show_images() {
        // XXX
    }

}
