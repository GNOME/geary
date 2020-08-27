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
    GLib.Log.set_writer_func(Geary.Logging.default_log_writer);
    if (logging_enabled) {
        Geary.Logging.log_to(stdout);
    }

    debug("Initialising...");

    // Ref it so it doesn't get free'ed right away
    GearyWebExtension instance = new GearyWebExtension(extension);
    instance.ref();
}

/**
 * A WebExtension that manages Geary-specific behaviours in web processes.
 */
public class GearyWebExtension : Object {

    private const string PAGE_STATE_OBJECT_NAME = "geary";
    private const string MESSAGE_RETURN_VALUE_NAME = "__return__";
    private const string MESSAGE_EXCEPTION_NAME = "__exception__";

    private const string[] ALLOWED_SCHEMES = { "cid", "geary", "data", "blob" };

    private const string REMOTE_LOAD_VAR = "_gearyAllowRemoteResourceLoads";

    private WebKit.WebExtension extension;


    public GearyWebExtension(WebKit.WebExtension extension) {
        this.extension = extension;
        extension.page_created.connect(on_page_created);
    }

    // XXX Conditionally enable while we still depend on WK2 <2.12
    private void on_console_message(WebKit.WebPage page,
                                    WebKit.ConsoleMessage message) {
        string source = message.get_source_id();
        debug("Console: [%s] %s %s:%u: %s",
              message.get_level().to_string().substring("WEBKIT_CONSOLE_MESSAGE_LEVEL_".length),
              message.get_source().to_string().substring("WEBKIT_CONSOLE_MESSAGE_SOURCE_".length),
              Geary.String.is_empty(source) ? "unknown" : source,
              message.get_line(),
              message.get_text()
        );
    }

    private bool on_send_request(WebKit.WebPage page,
                                 WebKit.URIRequest request,
                                 WebKit.URIResponse? response) {
        bool should_load = false;
        Soup.URI? uri = new Soup.URI(request.get_uri());
        if (uri != null && uri.get_scheme() in ALLOWED_SCHEMES) {
            // Always load internal resources
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
        JSC.Context context = frame.get_js_context();
        try {
            should_load = Util.JS.to_bool(context.get_value(REMOTE_LOAD_VAR));
        } catch (GLib.Error err) {
            debug(
                "Error checking PageState::allowRemoteImages: %s",
                err.message
            );
        }
        return should_load;
    }

    private void remote_image_load_blocked(WebKit.WebPage page) {
        WebKit.Frame frame = page.get_main_frame();
        JSC.Context context = frame.get_js_context();
        try {
            execute_script(
                context,
                "geary.remoteImageLoadBlocked();",
                GLib.Log.FILE,
                GLib.Log.METHOD,
                GLib.Log.LINE
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
        JSC.Context context = frame.get_js_context();
        try {
            execute_script(
                context,
                "geary.selectionChanged();",
                GLib.Log.FILE,
                GLib.Log.METHOD,
                GLib.Log.LINE
            );
        } catch (Error err) {
            debug("Error calling PageStates::selectionChanged: %s", err.message);
        }
    }

    private JSC.Value execute_script(JSC.Context context,
                                     string script,
                                     string file_name,
                                     string method_name,
                                     int line_number)
        throws Util.JS.Error {
        JSC.Value ret = context.evaluate_with_source_uri(
            script, -1, "geary:%s/%s".printf(file_name, method_name), line_number
        );
        Util.JS.check_exception(context);
        return ret;
    }

    private void on_page_created(WebKit.WebExtension extension,
                                 WebKit.WebPage page) {
        WebKit.Frame frame = page.get_main_frame();
        JSC.Context context = frame.get_js_context();
        context.set_value(
            REMOTE_LOAD_VAR,
            new JSC.Value.boolean(context, false)
        );

        page.console_message_sent.connect(on_console_message);
        page.send_request.connect(on_send_request);
        // XXX investigate whether the earliest supported
        // version of WK supports the DOM "selectionchanged"
        // event, and if so use that rather that doing it in
        // here in the extension
        page.get_editor().selection_changed.connect(() => {
                selection_changed(page);
            });
        page.user_message_received.connect(on_page_message_received);
    }

    private bool on_page_message_received(WebKit.WebPage page,
                                          WebKit.UserMessage message) {
        WebKit.Frame frame = page.get_main_frame();
        JSC.Context context = frame.get_js_context();
        JSC.Value page_state = context.get_value(PAGE_STATE_OBJECT_NAME);

        try {
            JSC.Value[]? call_param = null;
            GLib.Variant? message_param = message.parameters;
            if (message_param != null) {
                if (message_param.is_container()) {
                    size_t len = message_param.n_children();
                    call_param = new JSC.Value[len];
                    for (size_t i = 0; i < len; i++) {
                        call_param[i] = Util.JS.variant_to_value(
                            context,
                            message_param.get_child_value(i)
                        );
                    }
                } else {
                    call_param = {
                        Util.JS.variant_to_value(context, message_param)
                    };
                }
            }

            JSC.Value ret = page_state.object_invoke_methodv(
                message.name, call_param
            );

            // Must send a reply, even for void calls, otherwise
            // WebKitGTK will complain. So return a message return
            // rain hail or shine.
            // https://bugs.webkit.org/show_bug.cgi?id=215880

            message.send_reply(
                new WebKit.UserMessage(
                    MESSAGE_RETURN_VALUE_NAME,
                    Util.JS.value_to_variant(ret)
                )
            );
        } catch (GLib.Error err) {
            debug("Failed to handle message: %s", err.message);
        }

        return true;
    }

}
