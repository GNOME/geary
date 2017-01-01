/*
 * Copyright 2016 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * Initialises GearyWebExtension for WebKit web processes.
 */
public void webkit_web_extension_initialize_with_user_data(WebKit.WebExtension extension,
                                                           Variant data) {
    bool logging_enabled = data.get_boolean();

    Geary.Logging.init();
    if (logging_enabled)
        Geary.Logging.log_to(stdout);

    debug("Initialising...");

    // Ref it so it doesn't get free'ed right away
    GearyWebExtension instance = new GearyWebExtension(extension);
    instance.ref();
}

/**
 * A WebExtension that manages Geary-specific behaviours in web processes.
 */
public class GearyWebExtension : Object {


    private const string CID_PREFIX = "cid:";
    private const string DATA_PREFIX = "data:";

    private WebKit.WebExtension extension;


    public GearyWebExtension(WebKit.WebExtension extension) {
        this.extension = extension;
        extension.page_created.connect((extension, web_page) => {
                web_page.console_message_sent.connect(on_console_message);
                web_page.send_request.connect(on_send_request);
                web_page.get_editor().selection_changed.connect(() => {
                    selection_changed(web_page);
                });
            });
    }

    // XXX Conditionally enable while we still depend on WK2 <2.12
    private void on_console_message(WebKit.WebPage page,
                                    WebKit.ConsoleMessage message) {
        debug("Console: [%s] %s %s:%u: %s",
              message.get_level().to_string(),
              message.get_source().to_string(),
              message.get_source_id(),
              message.get_line(),
              message.get_text()
        );
    }

    private bool on_send_request(WebKit.WebPage page,
                                 WebKit.URIRequest request,
                                 WebKit.URIResponse? response) {
        bool should_load = false;
        string req_uri = request.get_uri();
        if (req_uri.has_prefix(CID_PREFIX) ||
            req_uri.has_prefix(DATA_PREFIX)) {
            // Always load images with these prefixes
            should_load = true;
        } else {
            // Only load anything else if remote image loading is
            // permitted
            if (should_load_remote_images(page)) {
                should_load = true;
            } else {
                remote_image_load_blocked(page);
            }
        }

        return should_load ? Gdk.EVENT_PROPAGATE : Gdk.EVENT_STOP; // LOL
    }

    private bool should_load_remote_images(WebKit.WebPage page) {
        bool should_load = false;
        WebKit.Frame frame = page.get_main_frame();
        JS.GlobalContext context = frame.get_javascript_global_context();
        try {
            JS.Value ret = execute_script(
                context, "geary.allowRemoteImages", int.parse("__LINE__")
            );
            should_load = ret.to_boolean(context);
        } catch (Error err) {
            debug(
                "Error checking PageState::allowRemoteImages: %s",
                err.message
            );
        }
        return should_load;
    }

    private void remote_image_load_blocked(WebKit.WebPage page) {
        WebKit.Frame frame = page.get_main_frame();
        JS.GlobalContext context = frame.get_javascript_global_context();
        try {
            execute_script(
                context, "geary.remoteImageLoadBlocked();", int.parse("__LINE__")
            );
        } catch (Error err) {
            debug(
                "Error calling PageState::remoteImageLoadBlocked: %s",
                err.message
            );
        }
    }

    private void selection_changed(WebKit.WebPage page) {
        WebKit.Frame frame = page.get_main_frame();
        JS.GlobalContext context = frame.get_javascript_global_context();
        try {
            execute_script(
                context, "geary.selectionChanged();", int.parse("__LINE__")
            );
        } catch (Error err) {
            debug("Error calling PageStates::selectionChanged: %s", err.message);
        }
    }

    private JS.Value execute_script(JS.Context context, string script, int line)
    throws Geary.JS.Error {
        JS.String js_script = new JS.String.create_with_utf8_cstring(script);
        JS.String js_source = new JS.String.create_with_utf8_cstring("__FILE__");
        JS.Value? err = null;
        try {
            JS.Value ret = context.evaluate_script(
                js_script, null, js_source, line, out err
            );
            Geary.JS.check_exception(context, err);
            return ret;
        } finally {
            js_script.release();
            js_source.release();
        }
    }

}
