/*
 * Copyright © 2016-2020 Michael Gratton <mike@vee.net>
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
    if (logging_enabled) {
        GLib.Log.set_writer_func(Geary.Logging.default_log_writer);
        Geary.Logging.log_to(GLib.stdout);
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

    // Keep these in sync with Components.WebView
    private const string MESSAGE_EXCEPTION = "__exception__";
    private const string MESSAGE_ENABLE_REMOTE_LOAD = "__enable_remote_load__";
    private const string MESSAGE_RETURN_VALUE = "__return__";

    private const string[] ALLOWED_SCHEMES = { "cid", "geary", "data", "blob" };

    private const string EXTENSION_CLASS_VAR = "_GearyWebExtension";
    private const string EXTENSION_CLASS_SEND = "send";
    private const string EXTENSION_CLASS_ALLOW_REMOTE_LOAD = "allowRemoteResourceLoad";

    private WebKit.WebExtension extension;


    public GearyWebExtension(WebKit.WebExtension extension) {
        this.extension = extension;
        extension.page_created.connect(on_page_created);
        WebKit.ScriptWorld.get_default().window_object_cleared.connect(on_window_object_cleared);
    }

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
        GLib.Uri? uri = null;
        try {
            uri = GLib.Uri.parse(request.get_uri(), NONE);
        } catch (GLib.UriError err) {
            warning("Invalid request URI: %s", err.message);
        }
        if (uri != null && uri.get_scheme() in ALLOWED_SCHEMES) {
            // Always load internal resources
            should_load = true;
        } else {
            // Only load anything else if remote resources loading is
            // permitted
            if (should_load_remote_resources(page)) {
                should_load = true;
            } else {
                page.send_message_to_view.begin(
                    new WebKit.UserMessage("remote_resource_load_blocked", null),
                    null
                );
            }
        }

        return should_load ? Gdk.EVENT_PROPAGATE : Gdk.EVENT_STOP; // LOL
    }

    private bool should_load_remote_resources(WebKit.WebPage page) {
        return page.get_data<string>(EXTENSION_CLASS_ALLOW_REMOTE_LOAD) != null;
    }

    private WebKit.UserMessage to_exception_message(string? name,
                                                    string? message,
                                                    string? backtrace = null,
                                                    string? source = null,
                                                    int line_number = -1,
                                                    int column_number = -1) {
        var detail = new GLib.VariantDict();
        if (name != null) {
            detail.insert_value("name", new GLib.Variant.string(name));
        }
        if (message != null) {
            detail.insert_value("message", new GLib.Variant.string(message));
        }
        if (backtrace != null) {
            detail.insert_value("backtrace", new GLib.Variant.string(backtrace));
        }
        if (source != null) {
            detail.insert_value("source", new GLib.Variant.string(source));
        }
        if (line_number > 0) {
            detail.insert_value("line_number", new GLib.Variant.uint32(line_number));
        }
        if (column_number > 0) {
            detail.insert_value("column_number", new GLib.Variant.uint32(column_number));
        }
        return new WebKit.UserMessage(
            MESSAGE_EXCEPTION,
            detail.end()
        );
    }

    private void on_page_created(WebKit.WebExtension extension,
                                 WebKit.WebPage page) {
        page.console_message_sent.connect(on_console_message);
        page.send_request.connect(on_send_request);
        page.user_message_received.connect(on_page_message_received);
    }

    private bool on_page_message_received(WebKit.WebPage page,
                                          WebKit.UserMessage message) {
        WebKit.Frame frame = page.get_main_frame();
        JSC.Context context = frame.get_js_context();
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

            JSC.Value page_state = context.get_value(PAGE_STATE_OBJECT_NAME);
            JSC.Value? ret = null;
            if (message.name == MESSAGE_ENABLE_REMOTE_LOAD) {
                page.set_data<string>(
                    EXTENSION_CLASS_ALLOW_REMOTE_LOAD,
                    EXTENSION_CLASS_ALLOW_REMOTE_LOAD
                );
                if (!page_state.is_undefined()) {
                    ret = page_state.object_invoke_methodv(
                        "loadRemoteResources", null
                    );
                }
            } else {
                ret = page_state.object_invoke_methodv(
                    message.name, call_param
                );
            }

            // Must send a reply, even for void calls, otherwise
            // WebKitGTK will complain. So return a message return
            // rain hail or shine.
            // https://bugs.webkit.org/show_bug.cgi?id=215880

            JSC.Exception? thrown = context.get_exception();
            if (thrown != null) {
                message.send_reply(
                    to_exception_message(
                        thrown.get_name(),
                        thrown.get_message(),
                        thrown.get_backtrace_string(),
                        thrown.get_source_uri(),
                        (int) thrown.get_line_number(),
                        (int) thrown.get_column_number()
                    )
                );
            } else {
                message.send_reply(
                    new WebKit.UserMessage(
                        MESSAGE_RETURN_VALUE,
                        ret != null ? Util.JS.value_to_variant(ret) : null
                    )
                );
            }
        } catch (GLib.Error err) {
            debug("Failed to handle message: %s", err.message);
        }

        return true;
    }

    private bool on_page_send_message(WebKit.WebPage page,
                                      GLib.GenericArray<JSC.Value> args) {
        WebKit.UserMessage? message = null;
        if (args.length > 0) {
            var name = args.get(0).to_string();
            GLib.Variant? parameters = null;
            if (args.length > 1) {
                JSC.Value param_value = args.get(1);
                try {
                    int len = Util.JS.to_int32(
                        param_value.object_get_property("length")
                    );
                    if (len == 1) {
                        parameters = Util.JS.value_to_variant(
                            param_value.object_get_property_at_index(0)
                        );
                    } else if (len > 1) {
                        parameters = Util.JS.value_to_variant(param_value);
                    }
                } catch (Util.JS.Error err) {
                    message = to_exception_message(
                        this.get_type().name(), err.message
                    );
                }
            }
            if (message == null) {
                message = new WebKit.UserMessage(name, parameters);
            }
        }
        if (message == null) {
            var log_message = "Not enough parameters for JS call to %s.%s()".printf(
                EXTENSION_CLASS_VAR,
                EXTENSION_CLASS_SEND
            );
            debug(log_message);
            message = to_exception_message(this.get_type().name(), log_message);
        }

        page.send_message_to_view.begin(message, null);
        return true;
    }

    private void on_window_object_cleared(WebKit.ScriptWorld world,
                                          WebKit.WebPage page,
                                          WebKit.Frame frame)
    {
        JSC.Context context = frame.get_js_context();

        var extension_class = context.register_class(
            this.get_type().name(),
            null,
            null,
            null
        );
        extension_class.add_method(
            EXTENSION_CLASS_SEND,
            (instance, values) => {
                return this.on_page_send_message(page, values);
            },
            GLib.Type.NONE
        );
        context.set_value(
            EXTENSION_CLASS_VAR,
            new JSC.Value.object(context, extension_class, extension_class)
        );
    }

}
