/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2017 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class ConversationWebView : ClientWebView {


    private const string DECEPTIVE_LINK_CLICKED = "deceptiveLinkClicked";

    // Key codes we don't forward on to the super class on key press
    // since we want to override them elsewhere, especially
    // ConversationListBox.
    private const uint[] BLACKLISTED_KEY_CODES = {
        Gdk.Key.space,
        Gdk.Key.KP_Space,
        Gdk.Key.Up,
        Gdk.Key.Down,
        Gdk.Key.Page_Up,
        Gdk.Key.Page_Down,
        Gdk.Key.Home,
        Gdk.Key.End
    };

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

    private static WebKit.UserStyleSheet? app_stylesheet = null;
    private static WebKit.UserScript? app_script = null;

    public static new void load_resources()
        throws Error {
        ConversationWebView.app_script = ClientWebView.load_app_script(
            "conversation-web-view.js"
        );
        ConversationWebView.app_stylesheet = ClientWebView.load_app_stylesheet(
            "conversation-web-view.css"
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

        register_message_handler(
            DECEPTIVE_LINK_CLICKED, on_deceptive_link_clicked
        );

        this.notify["preferred-height"].connect(() => queue_resize());
    }

    /**
     * Returns the current selection, for prefill as find text.
     */
    public async string? get_selection_for_find() throws Error{
        WebKit.JavascriptResult result = yield call(
            Geary.JS.callable("geary.getSelectionForFind"), null
        );
        return Util.WebKit.to_string(result);
    }

    /**
     * Returns the current selection, for quoting in a message.
     */
    public async string? get_selection_for_quoting() throws Error {
        WebKit.JavascriptResult result = yield call(
            Geary.JS.callable("geary.getSelectionForQuoting"), null
        );
        return Util.WebKit.to_string(result);
    }

    /**
     * Returns the y value for a element, by its id
     */
    public async int? get_anchor_target_y(string anchor_body)
        throws GLib.Error {
        WebKit.JavascriptResult result = yield call(
            Geary.JS.callable("geary.getAnchorTargetY")
            .string(anchor_body), null
        );
        return (int) Util.WebKit.to_number(result);
    }

    /**
     * Highlights user search terms in the message view.
     *
     * Returns the number of matching search terms.
     */
    public async uint highlight_search_terms(Gee.Collection<string> terms,
                                             GLib.Cancellable cancellable)
        throws GLib.IOError.CANCELLED {
        WebKit.FindController controller = get_find_controller();

        // Remove existing highlights
        controller.search_finish();

        // XXX WK2 doesn't deal with the multiple highlighting
        // required by search folder matches, only single highlighting
        // for a fine-like interface. For now, just highlight the
        // first term

        uint found = 0;

        SourceFunc callback = this.highlight_search_terms.callback;
        ulong found_handler = controller.found_text.connect((count) => {
                found = count;
                callback();
            });
        ulong not_found_handler = controller.failed_to_find_text.connect(() => {
                callback();
            });
        ulong cancelled_handler = cancellable.cancelled.connect(() => {
                callback();
            });

        controller.search(
            Geary.Collection.get_first(terms),
            WebKit.FindOptions.CASE_INSENSITIVE |
            WebKit.FindOptions.WRAP_AROUND,
            128
        );

        yield;

        controller.disconnect(found_handler);
        controller.disconnect(not_found_handler);
        cancellable.disconnect(cancelled_handler);

        if (cancellable.is_cancelled()) {
            throw new IOError.CANCELLED(
                "ConversationWebView highlight search terms cancelled"
            );
        }

        return found;
    }

    /**
     * Unmarks any search terms highlighted in the message view.
     */
    public void unmark_search_terms() {
        get_find_controller().search_finish();
    }

    public override bool key_press_event(Gdk.EventKey event) {
        // WebView consumes a number of key presses for scrolling
        // itself internally, but we want them to navigate around in
        // ConversationListBox, so don't forward any on.
        bool ret = Gdk.EVENT_PROPAGATE;
        if (!(((int) event.keyval) in BLACKLISTED_KEY_CODES)) {
            ret = base.key_press_event(event);
        }
        return ret;
    }


    public override void get_preferred_height(out int minimum_height,
                                              out int natural_height) {
        // XXX clamp height to something not too outrageous so we
        // don't get an XServer error trying to allocate a massive
        // window.
        const uint max_pixels = 8 * 1024 * 1024;
        int width = get_allocated_width();
        int height = this.preferred_height;
        if (height * width > max_pixels) {
            height = (int) Math.floor(max_pixels / (double) width);
        }

        minimum_height = natural_height = height;
    }

    // Overridden since we always what the view to be sized according
    // to the available space in the parent, not by the width of the
    // web view.
    public override void get_preferred_width(out int minimum_height,
                                             out int natural_height) {
        minimum_height = natural_height = 0;
    }

    private void on_deceptive_link_clicked(WebKit.JavascriptResult result) {
        try {
            unowned JS.GlobalContext context = result.get_global_context();
            JS.Object details = Util.WebKit.to_object(result);

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

            Gdk.Rectangle location = Gdk.Rectangle();
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
