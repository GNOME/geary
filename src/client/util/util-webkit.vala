/*
 * Copyright 2017-2019 Michael James Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Utility functions for WebKit objects.
 */
namespace Util.WebKit {

    /**
     * Returns a WebKit {@link WebKit.JavascriptResult} as a `bool`.
     *
     * This will raise a {@link Geary.JS.Error.TYPE} error if the
     * result is not a JavaScript `Boolean`.
     */
    public bool to_bool(global::WebKit.JavascriptResult result)
        throws Geary.JS.Error {
        unowned JS.GlobalContext context = result.get_global_context();
        unowned JS.Value value = result.get_value();
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
    public inline double to_number(global::WebKit.JavascriptResult result)
        throws Geary.JS.Error {
        return Geary.JS.to_number(result.get_global_context(),
                                  result.get_value());
    }

    /**
     * Returns a WebKit {@link WebKit.JavascriptResult} as a Vala {@link string}.
     *
     * This will raise a {@link Geary.JS.Error.TYPE} error if the
     * result is not a JavaScript `String`.
     */
    public inline string to_string(global::WebKit.JavascriptResult result)
        throws Geary.JS.Error {
        return Geary.JS.to_string(result.get_global_context(),
                                  result.get_value());
    }

    /**
     * Converts a WebKit {@link WebKit.JavascriptResult} to a {@link string}.
     *
     * Unlike the other `get_foo_result` methods, this will coax the
     * result to a string, effectively by calling the JavaScript
     * `toString()` method on it, and returning that value.
     */
    public string as_string(global::WebKit.JavascriptResult result)
        throws Geary.JS.Error {
        unowned JS.GlobalContext context = result.get_global_context();
        unowned JS.Value js_str_value = result.get_value();
        JS.Value? err = null;
        JS.String js_str = js_str_value.to_string_copy(context, out err);
        Geary.JS.check_exception(context, err);
        return Geary.JS.to_native_string(js_str);
    }

    /**
     * Returns a WebKit {@link WebKit.JavascriptResult} as an Object.
     *
     * This will raise a {@link Geary.JS.Error.TYPE} error if the
     * result is not a JavaScript `Object`.
     *
     * Return type is nullable as a workaround for Bug 778046, it will
     * never actually be null.
     */
    public JS.Object? to_object(global::WebKit.JavascriptResult result)
        throws Geary.JS.Error {
        return Geary.JS.to_object(result.get_global_context(),
                                  result.get_value());
    }

}
