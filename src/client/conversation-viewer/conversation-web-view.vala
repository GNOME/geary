/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2017 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class ConversationWebView : ClientWebView {

    private const string USER_CSS = "user-message.css";

    private const string DECEPTIVE_LINK_CLICKED = "deceptiveLinkClicked";

    /** Specifies the type of deceptive link text when clicked. */
    public enum DeceptiveText {
        // Keep this in sync with JS ConversationPageState
        /** No deceptive text found. */
        NOT_DECEPTIVE = 0,
        /** The link had an invalid HREF value. */
        DECEPTIVE_HREF = 1,
        /** The domain of the link's text did not match the HREF. */
        DECEPTIVE_DOMAIN = 2;
    }

    private static WebKit.UserStyleSheet? user_stylesheet = null;
    private static WebKit.UserStyleSheet? app_stylesheet = null;
    private static WebKit.UserScript? app_script = null;

    public static void load_resources(File user_dir)
        throws Error {
        ConversationWebView.app_script = ClientWebView.load_app_script(
            "conversation-web-view.js"
        );
        ConversationWebView.app_stylesheet = ClientWebView.load_app_stylesheet(
            "conversation-web-view.css"
        );
        ConversationWebView.user_stylesheet = ClientWebView.load_user_stylesheet(
            user_dir.get_child("user-message.css")
        );
    }


    /** Emitted when the user clicks on a link with deceptive text. */
    public signal void deceptive_link_clicked(
        DeceptiveText reason, string text, string href, Gdk.Rectangle location
    );


    public ConversationWebView(Configuration config) {
        base(config);
        this.user_content_manager.add_script(ConversationWebView.app_script);
        this.user_content_manager.add_style_sheet(ConversationWebView.app_stylesheet);
        if (ConversationWebView.user_stylesheet != null) {
            this.user_content_manager.add_style_sheet(ConversationWebView.user_stylesheet);
        }

        register_message_handler(
            DECEPTIVE_LINK_CLICKED, on_deceptive_link_clicked
        );
    }

    /**
     * Returns the current selection, for prefill as find text.
     */
    public async string? get_selection_for_find() throws Error{
        WebKit.JavascriptResult result = yield this.run_javascript(
            "geary.getSelectionForFind();", null
        );
        return WebKitUtil.to_string(result);
    }

    /**
     * Returns the current selection, for quoting in a message.
     */
    public async string? get_selection_for_quoting() throws Error {
        WebKit.JavascriptResult result = yield this.run_javascript(
            "geary.getSelectionForQuoting();", null
        );
        return WebKitUtil.to_string(result);
    }

    private void on_deceptive_link_clicked(WebKit.JavascriptResult result) {
        try {
            JS.GlobalContext context = result.get_global_context();
            JS.Object details = WebKitUtil.to_object(result);

            uint reason = (uint) Geary.JS.to_number(
                context,
                Geary.JS.get_property(context, details, "reason"));

            string href = Geary.JS.to_string(
                context,
                Geary.JS.get_property(context, details, "href"));

            string text = Geary.JS.to_string(
                context,
                Geary.JS.get_property(context, details, "text"));

            JS.Object js_location = Geary.JS.to_object(
                context,
                Geary.JS.get_property(context, details, "location"));

            Gdk.Rectangle location = new Gdk.Rectangle();
            location.x = (int) Geary.JS.to_number(
                context,
                Geary.JS.get_property(context, js_location, "x"));
            location.y = (int) Geary.JS.to_number(
                context,
                Geary.JS.get_property(context, js_location, "y"));
            location.width = (int) Geary.JS.to_number(
                context,
                Geary.JS.get_property(context, js_location, "width"));
            location.height = (int) Geary.JS.to_number(
                context,
                Geary.JS.get_property(context, js_location, "height"));

            deceptive_link_clicked((DeceptiveText) reason, text, href, location);
        } catch (Geary.JS.Error err) {
            debug("Could not get deceptive link param: %s", err.message);
        }
    }

}
