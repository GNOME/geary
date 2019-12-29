/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Stores a map of name-values pairs as ''ASCII'' (i.e. 7-bit) strings.
 */

public class Geary.GenericCapabilities : BaseObject {
    public string name_separator { get; private set; }
    public string? value_separator { get; private set; }

    // All params must be nullable to support both libgee 0.8.0 and 0.8.6 (for Quantal and Rarring, respectively.)
    // This behavior was changed in the following libgee commit:
    // https://git.gnome.org/browse/libgee/commit/?id=5a35303cb04154d0e929a7d8895d4a4812ba7a1c
    private Gee.HashMultiMap<string, string?> map = new Gee.HashMultiMap<string, string?>(
        Ascii.nullable_stri_hash, Ascii.nullable_stri_equal, Ascii.nullable_stri_hash, Ascii.nullable_stri_equal);

    /**
     * Creates an empty set of capabilities.
     */
    public GenericCapabilities(string name_separator, string? value_separator) {
        assert(!String.is_empty(name_separator));

        this.name_separator = name_separator;
        this.value_separator = !String.is_empty(value_separator) ? value_separator : null;
    }

    public bool is_empty() {
        return (map.size == 0);
    }

    /**
     * Returns true only if the capability was named as available by the server.
     */
    public bool has_capability(string name) {
        return map.contains(name);
    }

    /**
     * Returns true only if the capability and the associated setting were both named as available
     * by the server.
     */
    public bool has_setting(string name, string? setting) {
        if (!map.contains(name))
            return false;

        if (String.is_empty(setting))
            return true;

        return map.get(name).contains(setting);
    }

    /**
     * Returns null if either the capability is available but has no associated settings, or if the
     * capability is not available.  Thus, use has_capability() to determine if available, then
     * this method to get its value (if one is expected).  Often has_setting() is a better choice.
     */
    public Gee.Collection<string>? get_settings(string name) {
        Gee.Collection<string> settings = map.get(name);

        return (settings.size > 0) ? settings : null;
    }

    public Gee.Set<string>? get_all_names() {
        Gee.Set<string> names = map.get_keys();

        return (names.size > 0) ? names : null;
    }

    public virtual string to_string() {
        Gee.Set<string>? names = get_all_names();
        if (names == null || names.size == 0)
            return "";

        StringBuilder builder = new StringBuilder();
        foreach (string name in names) {
            Gee.Collection<string>? settings = get_settings(name);
            if (settings == null || settings.size == 0) {
                append(builder, name);
            } else {
                foreach (string setting in settings) {
                    if (String.is_empty(setting))
                        append(builder, name);
                    else
                        append(builder, "\"%s%s%s\"".printf(name, name_separator, setting));
                }
            }
        }

        return builder.str;
    }

    private inline void append(StringBuilder builder, string text) {
        if (!String.is_empty(builder.str))
            builder.append(String.is_empty(value_separator) ? " " : value_separator);

        builder.append(text);
    }

    protected bool parse_and_add_capability(string text) {
        string[] name_values = text.split(name_separator, 2);
        switch (name_values.length) {
            case 1:
                add_capability(name_values[0]);
            break;

            case 2:
                if (value_separator == null) {
                    add_capability(name_values[0], name_values[1]);
                } else {
                    // break up second token for multiple values
                    string[] values = name_values[1].split(value_separator);
                    if (values.length <= 1) {
                        add_capability(name_values[0], name_values[1]);
                    } else {
                        foreach (string value in values)
                            add_capability(name_values[0], value);
                    }
                }
            break;

            default:
                return false;
        }

        return true;
    }

    private inline void add_capability(string name, string? setting = null) {
        this.map.set(name, String.is_empty(setting) ? null : setting);
    }

}
