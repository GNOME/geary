/*
 * Copyright 2017 Michael James Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Utility functions for WebKit objects.
 */
namespace WebKitUtil {

    /**
     * Returns a WebKit {@link WebKit.JavascriptResult} as a `bool`.
     *
     * This will raise a {@link Geary.JS.Error.TYPE} error if the
     * result is not a JavaScript `Boolean`.
     */
    public bool to_bool(WebKit.JavascriptResult result)
        throws Geary.JS.Error {
        JS.GlobalContext context = result.get_global_context();
        JS.Value value = result.get_value();
        if (!value.is_boolean(context)) {
            throw new Geary.JS.Error.TYPE("Result is not a JS Boolean object");
        }
        return value.to_boolean(context);
    }

    /**
     * Returns a WebKit {@link WebKit.JavascriptResult} as a `double`.
     *
     * This will raise a {@link Geary.JS.Error.TYPE} error if the
     * result is not a JavaScript `Number`.
     */
    public double to_number(WebKit.JavascriptResult result)
        throws Geary.JS.Error {
        JS.GlobalContext context = result.get_global_context();
        JS.Value value = result.get_value();
        if (!value.is_number(context)) {
            throw new Geary.JS.Error.TYPE("Result is not a JS Number object");
        }

        JS.Value? err = null;
        double number = value.to_number(context, out err);
        Geary.JS.check_exception(context, err);
        return number;
    }

    /**
     * Returns a WebKit {@link WebKit.JavascriptResult} as a Vala {@link string}.
     *
     * This will raise a {@link Geary.JS.Error.TYPE} error if the
     * result is not a JavaScript `String`.
     */
    public string? to_string(WebKit.JavascriptResult result)
        throws Geary.JS.Error {
        JS.GlobalContext context = result.get_global_context();
        JS.Value js_str_value = result.get_value();
        if (!js_str_value.is_string(context)) {
            throw new Geary.JS.Error.TYPE("Result is not a JS String object");
        }

        JS.Value? err = null;
        JS.String js_str = js_str_value.to_string_copy(context, out err);
        Geary.JS.check_exception(context, err);

        return Geary.JS.to_string_released(js_str);
    }

    /**
     * Converts a WebKit {@link WebKit.JavascriptResult} to a {@link string}.
     *
     * Unlike the other `get_foo_result` methods, this will coax the
     * result to a string, effectively by calling the JavaScript
     * `toString()` method on it, and returning that value.
     */
    public string? as_string(WebKit.JavascriptResult result)
        throws Geary.JS.Error {
        JS.GlobalContext context = result.get_global_context();
        JS.Value js_str_value = result.get_value();
        JS.Value? err = null;
        JS.String js_str = js_str_value.to_string_copy(context, out err);
        Geary.JS.check_exception(context, err);
        return Geary.JS.to_string_released(js_str);
    }

}
