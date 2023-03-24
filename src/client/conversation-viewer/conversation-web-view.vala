/*
 * Copyright © 2016 Software Freedom Conservancy Inc.
 * Copyright © 2017-2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class ConversationWebView : Components.WebView {


    private const string[] HTML_PLACEHOLDERS = {
        "@TO@",
        "@CC@",
        "@BCC@",
        "@CONTENT_POLICY_TITLE@",
        "@CONTENT_POLICY_SUBTITLE@"
    };
    private static string[] HTML_TRANSLATIONS = {
        gettext("To"),
        gettext("Cc"),
        gettext("Bcc"),
        gettext("Remote images not shown"),
        gettext("Only show remote images from senders you trust.")
    };

    private static Gee.HashMap<string,string> html_translations =
        new Gee.HashMap<string,string>();

    static construct {
        uint i = 0;
        foreach (string placeholder in HTML_PLACEHOLDERS) {
            html_translations[placeholder] = HTML_TRANSLATIONS[i++];
        }
    }

    private Gee.HashMap<string,string> translated_resources =
        new Gee.HashMap<string,string>();

    private const string DECEPTIVE_LINK_CLICKED = "deceptive_link_clicked";
    private const string IMAGES_POLICY_CLICKED = "images_policy_clicked";

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

    /** Emitted when the user clicks on a link with deceptive text. */
    public signal void deceptive_link_clicked(
        DeceptiveText reason, string text, string href, Gdk.Rectangle location
    );

    /** Emitted when the user clicks image policy button. */
    public signal void images_policy_clicked(uint x, uint y, uint width, uint height);

    /**
     * Constructs a new web view for displaying an email message body.
     *
     * A new WebKitGTK WebProcess will be constructed for this view.
     */
    public ConversationWebView(Application.Configuration config) {
        base(config);
        init();

        Components.WebView.default_context.register_uri_scheme("html", (req) => {
            WebKit.WebView? view = req.get_web_view() as WebKit.WebView;
            if (view != null) {
                handle_html_request(req);
            }
        });
        Components.WebView.default_context.register_uri_scheme("avatar", (req) => {
            WebKit.WebView? view = req.get_web_view() as WebKit.WebView;
            if (view != null) {
                handle_avatar_request(req);
            }
        });
        Components.WebView.default_context.register_uri_scheme("iframe", (req) => {
            WebKit.WebView? view = req.get_web_view() as WebKit.WebView;
            if (view != null) {
                handle_iframe_request(req);
            }
        });

        this.add_script("conversation-web-view.js");
        this.add_script("conversation-email-list.js");
        this.add_script("conversation-email.js");

        this.add_style_sheet("conversation-web-view.css");
        this.add_style_sheet("conversation-email-list.css");
        this.add_style_sheet("conversation-email.css");
    }

    /**
     * Returns the current selection, for prefill as find text.
     */
    public async string? get_selection_for_find() throws Error{
        return yield call_returning<string?>(
            Util.JS.callable("geary.getSelectionForFind"), null
        );
    }

    /**
     * Returns the current selection, for quoting in a message.
     */
    public async string? get_selection_for_quoting() throws Error {
        return yield call_returning<string?>(
            Util.JS.callable("geary.getSelectionForQuoting"), null
        );
    }

    /**
     * Returns the y value for a element, by its id
     */
    public async int? get_anchor_target_y(string anchor_body)
        throws GLib.Error {
        return yield call_returning<int?>(
            Util.JS.callable("geary.getAnchorTargetY").string(anchor_body), null
        );
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
        bool finished = false;

        SourceFunc callback = this.highlight_search_terms.callback;
        ulong found_handler = controller.found_text.connect((count) => {
                if (!finished) {
                    found = count;
                    callback();
                }
            });
        ulong not_found_handler = controller.failed_to_find_text.connect(() => {
                if (!finished) {
                    callback();
                }
            });
        ulong cancelled_handler = cancellable.cancelled.connect(() => {
                if (!finished) {
                    // Do this at idle since per the docs for
                    // GLib.Cancellable.disconnect, disconnecting a
                    // handler from within a handler causes a deadlock.
                    GLib.Idle.add(() => callback());
                }
            });

        controller.search(
            Geary.Collection.first(terms),
            WebKit.FindOptions.CASE_INSENSITIVE |
            WebKit.FindOptions.WRAP_AROUND,
            128
        );

        yield;

        finished = true;
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

    /**
     * Add script to web view
     */
    public void add_script(string name) {
        try {
            var script = Components.WebView.load_app_script(name);
            this.user_content_manager.add_script(script);
        } catch (GLib.Error err) {
            error("Can't load script: %s", err.message);
        }
    }

    /**
     * Add style sheet to web view
     */
    public void add_style_sheet(string name) {
        try {
            var style_sheet = Components.WebView.load_app_stylesheet(name);
            this.user_content_manager.add_style_sheet(style_sheet);
        } catch (GLib.Error err) {
            error("Can't load style sheet: %s", err.message);
        }
    }

    protected virtual void handle_avatar_request(WebKit.URISchemeRequest request) {
        request.finish_error(new FileError.NOENT("Unknown avatar URL"));
    }

    protected virtual void handle_iframe_request(WebKit.URISchemeRequest request) {
        request.finish_error(new FileError.NOENT("Unknown iframe URL"));
    }

    private void init() {
        register_message_callback(
            DECEPTIVE_LINK_CLICKED, on_deceptive_link_clicked
        );
        register_message_callback(
            IMAGES_POLICY_CLICKED, on_images_policy_clicked
        );
    }

    private void on_deceptive_link_clicked(GLib.Variant? parameters) {
        var dict = new GLib.VariantDict(parameters);
        uint reason = (uint) dict.lookup_value(
            "reason", GLib.VariantType.DOUBLE
        ).get_double();

        string href = dict.lookup_value(
            "href", GLib.VariantType.STRING
        ).get_string();

        string text = dict.lookup_value(
            "text", GLib.VariantType.STRING
        ).get_string();

        Gdk.Rectangle location = Gdk.Rectangle();
        var location_dict = new GLib.VariantDict(
            dict.lookup_value("location", GLib.VariantType.VARDICT)
        );
        location.x = (int) location_dict.lookup_value(
            "x", GLib.VariantType.DOUBLE
        ).get_double();
        location.y = (int) location_dict.lookup_value(
            "y", GLib.VariantType.DOUBLE
        ).get_double();
        location.width = (int) location_dict.lookup_value(
            "width", GLib.VariantType.DOUBLE
        ).get_double();
        location.height = (int) location_dict.lookup_value(
            "height", GLib.VariantType.DOUBLE
        ).get_double();

        deceptive_link_clicked(
            (DeceptiveText) reason, text, href, location
        );
    }

    private void on_images_policy_clicked(GLib.Variant? parameters) {
        var dict = new GLib.VariantDict(parameters);
        uint x = (uint) dict.lookup_value(
            "x", GLib.VariantType.DOUBLE
        ).get_double();
        uint y = (uint) dict.lookup_value(
            "y", GLib.VariantType.DOUBLE
        ).get_double();
        uint width = (uint) dict.lookup_value(
            "width", GLib.VariantType.DOUBLE
        ).get_double();
        uint height = (uint) dict.lookup_value(
            "height", GLib.VariantType.DOUBLE
        ).get_double();

        images_policy_clicked(x, y, width, height);
    }

    private void handle_html_request(WebKit.URISchemeRequest request) {
        try {
            string html_path = request.get_path();
            string resource;

            if (html_path in this.translated_resources.keys) {
                resource = this.translated_resources[html_path];
            } else {
                resource = GioUtil.read_resource(html_path);

                foreach (string placeholder in HTML_PLACEHOLDERS) {
                    resource = resource.replace(placeholder, html_translations[placeholder]);
                }
                this.translated_resources[html_path] = resource;
            }

            Geary.Memory.Buffer buf = new Geary.Memory.StringBuffer(resource);
            request.finish(buf.get_input_stream(), buf.size, null);
        } catch (GLib.Error err) {
            request.finish_error(err);
        }
    }
}



