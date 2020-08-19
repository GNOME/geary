/*
 * Copyright 2017,2019 Michael James Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * Utility functions for WebKit JavaScriptCore (JSC) objects.
 */
namespace Util.JS {

    /**
     * Errors produced by functions in {@link Util.JS}.
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
     * Returns a JSC Value as a bool.
     *
     * This will raise a {@link Util.JS.Error.TYPE} error if the
     * value is not a JavaScript `Boolean`.
     */
    public bool to_bool(JSC.Value value)
        throws Util.JS.Error {
        if (!value.is_boolean()) {
            throw new Util.JS.Error.TYPE("Value is not a JS Boolean object");
        }
        bool boolean = value.to_boolean();
        Util.JS.check_exception(value.context);
        return boolean;
    }

    /**
     * Returns a JSC Value as a double.
     *
     * This will raise a {@link Util.JS.Error.TYPE} error if the
     * value is not a JavaScript `Number`.
     */
    public double to_double(JSC.Value value)
        throws Util.JS.Error {
        if (!value.is_number()) {
            throw new Util.JS.Error.TYPE("Value is not a JS Number object");
        }

        double number = value.to_double();
        Util.JS.check_exception(value.context);
        return number;
    }

    /**
     * Returns a JSC Value as an int32.
     *
     * This will raise a {@link Util.JS.Error.TYPE} error if the
     * value is not a JavaScript `Number`.
     */
    public int32 to_int32(JSC.Value value)
        throws Util.JS.Error {
        if (!value.is_number()) {
            throw new Util.JS.Error.TYPE("Value is not a JS Number object");
        }

        int32 number = value.to_int32();
        Util.JS.check_exception(value.context);
        return number;
    }

    /**
     * Returns a JSC Value as a string.
     *
     * This will raise a {@link Util.JS.Error.TYPE} error if the
     * value is not a JavaScript `String`.
     */
    public string to_string(JSC.Value value)
        throws Util.JS.Error {
        if (!value.is_string()) {
            throw new Util.JS.Error.TYPE("Value is not a JS String object");
        }

        string str = value.to_string();
        Util.JS.check_exception(value.context);
        return str;
    }

    /**
     * Returns the value of an object property.
     *
     * This will raise a {@link Util.JS.Error.TYPE} error if the
     * value is not an object or does not contain the named property.
     */
    public inline JSC.Value get_property(JSC.Value value,
                                         string name)
        throws Util.JS.Error {
        if (!value.is_object()) {
            throw new Util.JS.Error.TYPE("Value is not a JS Object");
        }

        JSC.Value property = value.object_get_property(name);
        Util.JS.check_exception(value.context);
        return property;
    }

    /**
     * Checks an JS exception returned from a JSC call.
     *
     * If the given context has a current exception, it will cleared
     * and a {@link Util.JS.Error} will be thrown.
     */
    public inline void check_exception(JSC.Context context)
        throws Error {
        JSC.Exception? exception = context.get_exception();
        if (exception != null) {
            context.clear_exception();
            throw new Error.EXCEPTION(
                "JS exception thrown: %s", exception.to_string()
            );
        }
    }

    /**
     * Escapes a string so as to be safe to use as a JS string literal.
     *
     * This does not append opening or closing quotes.
     */
    public string escape_string(string value) {
        StringBuilder builder = new StringBuilder.sized(value.length);
        for (int i = 0; i < value.length; i++) {
            if (value.valid_char(i)) {
                unichar c = value.get_char(i);
                switch (c) {
                case '\x00':
                    builder.append("\x00");
                    break;
                case '\'':
                    builder.append("\\\'");
                    break;
                case '"':
                    builder.append("\\\"");
                    break;
                case '\\':
                    builder.append("\\\\");
                    break;
                case '\n':
                    builder.append("\\n");
                    break;
                case '\r':
                    builder.append("\\r");
                    break;
                case '\x0b':
                    builder.append("\x0b");
                    break;
                case '\t':
                    builder.append("\\t");
                    break;
                case '\b':
                    builder.append("\\b");
                    break;
                case '\f':
                    builder.append("\\f");
                    break;
                default:
                    builder.append_unichar(c);
                    break;
                }
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
     * A class for constructing a well formed, safe, invocable JS call.
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
