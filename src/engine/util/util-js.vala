/*
 * Copyright 2017 Michael James Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Utility functions for WebKit JavaScriptCore (JSC) objects.
 */
namespace Geary.JS {

    /**
     * Errors produced by functions in {@link Geary.JS}.
     */
    public errordomain Error {
        /**
         * A JS exception was thrown performing a function call.
         */
        EXCEPTION,

        /**
         * A {@link JS.Value} was not of the expected type.
         */
        TYPE
    }

    /**
     * Determines if a {@link JS.Value} object is {{{null}}}.
     *
     * @return `true` if `js` is `null` or has a {@link JS.Type} of
     * `NULL` according to `context`.
     */
    public inline bool is_null(global::JS.Context context,
                               global::JS.Value? js) {
        return (js == null || js.get_type(context) == global::JS.Type.NULL);
    }

    /**
     * Returns a JSC {@link JS.String} as a Vala {@link string}.
     */
    public inline string to_string_released(global::JS.String js) {
        int len = js.get_maximum_utf8_cstring_size();
        string str = string.nfill(len, 0);
        js.get_utf8_cstring(str, len);
        js.release();
        return str;
    }

    /**
     * Checks an JS exception returned from a JSC call.
     *
     * This method will raise a {@link Geary.JS.Error} if the given
     * `err_value` is not null (in a Vala or JS sense).
     */
    public inline void check_exception(global::JS.Context context,
                                       global::JS.Value? err_value)
        throws Error {
        if (!is_null(context, err_value)) {
            global::JS.Value? nested_err = null;
            global::JS.Type err_type = err_value.get_type(context);
            global::JS.String err_str =
                err_value.to_string_copy(context, out nested_err);

            if (!is_null(context, nested_err)) {
                throw new Error.EXCEPTION(
                    "Nested exception getting exception %s as a string",
                    err_type.to_string()
                );
            }

            throw new Error.EXCEPTION(
                "JS exception thrown [%s]: %s"
                .printf(err_type.to_string(), to_string_released(err_str))
            );
        }
    }

}
