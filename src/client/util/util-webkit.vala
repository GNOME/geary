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
     * Returns a WebKit JavascriptResult as a `bool`.
     *
     * This will raise a {@link Geary.JS.Error.TYPE} error if the
     * result is not a JavaScript `Boolean`.
     */
    public bool to_bool(global::WebKit.JavascriptResult result)
        throws Geary.JS.Error {
        return Geary.JS.to_bool(result.get_js_value());
    }

    /**
     * Returns a WebKit JavascriptResult as a `double`.
     *
     * This will raise a {@link Geary.JS.Error.TYPE} error if the
     * result is not a JavaScript `Number`.
     */
    public inline double to_int32(global::WebKit.JavascriptResult result)
        throws Geary.JS.Error {
        return Geary.JS.to_double(result.get_js_value());
    }

    /**
     * Returns a WebKit JavascriptResult as a `int32`.
     *
     * This will raise a {@link Geary.JS.Error.TYPE} error if the
     * result is not a JavaScript `Number`.
     */
    public inline int32 to_double(global::WebKit.JavascriptResult result)
        throws Geary.JS.Error {
        return Geary.JS.to_int32(result.get_js_value());
    }

    /**
     * Returns a WebKit JavascriptResult as a GLib string.
     *
     * This will raise a {@link Geary.JS.Error.TYPE} error if the
     * result is not a JavaScript `String`.
     */
    public inline string to_string(global::WebKit.JavascriptResult result)
        throws Geary.JS.Error {
        return Geary.JS.to_string(result.get_js_value());
    }

    /**
     * Converts a WebKit JavascriptResult to a GLib string.
     *
     * Unlike the other `get_foo_result` methods, this will coax the
     * result to a string, effectively by calling the JavaScript
     * `toString()` method on it, and returning that value.
     */
    public string as_string(global::WebKit.JavascriptResult result)
        throws Geary.JS.Error {
        JSC.Value value = result.get_js_value();
        string str = value.to_string();
        Geary.JS.check_exception(value.context);
        return str;
    }

}
