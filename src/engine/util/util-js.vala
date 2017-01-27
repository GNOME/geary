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
     * Returns a JSC Value as a number.
     *
     * This will raise a {@link Geary.JS.Error.TYPE} error if the
     * value is not a JavaScript `Number`.
     */
    public double to_number(global::JS.Context context,
                            global::JS.Value value)
        throws Geary.JS.Error {
        if (!value.is_number(context)) {
            throw new Geary.JS.Error.TYPE("Value is not a JS Number object");
        }

        global::JS.Value? err = null;
        double number = value.to_number(context, out err);
        Geary.JS.check_exception(context, err);
        return number;
    }

    /**
     * Returns a JSC Value as a string.
     *
     * This will raise a {@link Geary.JS.Error.TYPE} error if the
     * value is not a JavaScript `String`.
     */
    public string to_string(global::JS.Context context,
                            global::JS.Value value)
        throws Geary.JS.Error {
        if (!value.is_string(context)) {
            throw new Geary.JS.Error.TYPE("Value is not a JS String object");
        }

        global::JS.Value? err = null;
        global::JS.String js_str = value.to_string_copy(context, out err);
        Geary.JS.check_exception(context, err);

        return Geary.JS.to_string_released(js_str);
    }

    /**
     * Returns a JSC Value as an object.
     *
     * This will raise a {@link Geary.JS.Error.TYPE} error if the
     * value is not a JavaScript `Object`.
     */
    public global::JS.Object to_object(global::JS.Context context,
                                       global::JS.Value value)
        throws Geary.JS.Error {
        if (!value.is_object(context)) {
            throw new Geary.JS.Error.TYPE("Value is not a JS Object");
        }

        global::JS.Value? err = null;
        global::JS.Object js_obj = value.to_object(context, out err);
        Geary.JS.check_exception(context, err);

        return js_obj;
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
     * Returns the value of an object's property.
     *
     * This will raise a {@link Geary.JS.Error.TYPE} error if the
     * object does not contain the named property.
     */
    public inline global::JS.Value get_property(global::JS.Context context,
                                                global::JS.Object object,
                                                string name)
        throws Geary.JS.Error {
        global::JS.String js_name = new global::JS.String.create_with_utf8_cstring(name);
        global::JS.Value? err = null;
        global::JS.Value prop = object.get_property(context, js_name, out err);
        try {
            Geary.JS.check_exception(context, err);
        } finally {
            js_name.release();
        }
        return prop;
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

    /**
     * Escapes a string so as to be safte to use as a JS string literal.
     *
     * This does not append opening or closing quotes.
     */
    public string escape_string(string value) {
        const unichar[] RESERVED = {
            '\x00', '\'', '"', '\\', '\n', '\r', '\v', '\t', '\b', '\f'
        };
        StringBuilder builder = new StringBuilder.sized(value.length);
        for (int i = 0; i < value.length; i++) {
            if (value.valid_char(i)) {
                unichar c = value.get_char(i);
                if (c in RESERVED) {
                    builder.append_c('\\');
                }
                builder.append_unichar(c);
            }
        }
        return (string) builder.data;
    }

    /**
     * Convenience method for returning a new Callable instance.
     */
    public Callable callable(string base_name) {
        return new Callable(base_name);
    }

    /**
     * A class for constructing a well formed, safe, invokable JS call.
     */
    public class Callable {

        private string base_name;
        private string[] safe_args = new string[0];


        public Callable(string base_name) {
            this.base_name = base_name;
        }

        public string to_string() {
            return base_name + "(" + global::string.joinv(",", safe_args) + ");";
        }

        public Callable string(string value) {
            add_param("\"" + escape_string(value) + "\"");
            return this;
        }

        public Callable double(double value) {
            add_param(value.to_string());
            return this;
        }

        public Callable int(int value) {
            add_param(value.to_string());
            return this;
        }

        public Callable bool(bool value) {
            add_param(value ? "true" : "false");
            return this;
        }

        private inline void add_param(string value) {
            this.safe_args += value;
        }

    }

}
