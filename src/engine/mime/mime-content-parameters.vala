/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Content parameters (for {@link ContentType} and {@link ContentDisposition}).
 *
 * This class is immutable.
 */
public class Geary.Mime.ContentParameters : BaseObject {
    public int size {
        get {
            return params.size;
        }
    }

    public Gee.Collection<string> attributes {
        owned get {
            return params.keys;
        }
    }

    // See get_parameters() for why the keys but not the values are stored case-insensitive
    private Gee.HashMap<string, string> params = new Gee.HashMap<string, string>(
        Ascii.stri_hash, Ascii.stri_equal);

    /**
     * Create a mapping of content parameters.
     *
     * A Gee.Map may be supplied to initialize the parameter attributes (names) and values.
     *
     * Note that params may be any kind of Map, but they will be stored internally in a Map that
     * uses case-insensitive keys.  See {@link get_parameters} for more details.
     */
    public ContentParameters(Gee.Map<string, string>? params = null) {
        if (params != null && params.size > 0)
            Collection.map_set_all<string, string>(this.params, params);
    }

    /**
     * Create a mapping of content parameters.
     *
     * Note that the given params must be a two-dimensional array,
     * where each element contains a key/value pair.
     */
    public ContentParameters.from_array(string[,] params) {
        for (int i = 0; i < params.length[0]; i++) {
            this.params.set(params[i,0], params[i,1]);
        }
    }

    internal ContentParameters.from_gmime(GMime.ParamList gmime) {
        var parameters = new Gee.HashMap<string,string>();
        for (int i = 0; i < gmime.length(); i++) {
            var param = gmime.get_parameter_at(i);
            parameters.set(param.name, param.value);
        }
        this(parameters);
    }

    /**
     * A read-only mapping of parameter attributes (names) and values.
     *
     * Note that names are stored as case-insensitive tokens.  The MIME specification does allow
     * for some parameter values to be case-sensitive and so they are stored as such.  It is up
     * to the caller to use the right comparison method.
     *
     * @see has_value_ci
     * @see has_value_cs
     */
    public Gee.Map<string, string> get_parameters() {
        return params.read_only_view;
    }

    /**
     * Returns the parameter value for the attribute name.
     *
     * Returns null if not present.
     */
    public string? get_value(string attribute) {
        return params.get(attribute);
    }

    /**
     * Returns true if the attribute has the supplied value (case-insensitive comparison).
     *
     * @see has_value_cs
     */
    public bool has_value_ci(string attribute, string value) {
        string? stored = params.get(attribute);

        return (stored != null) ? Ascii.stri_equal(stored, value) : false;
    }

    /**
     * Returns true if the attribute has the supplied value (case-sensitive comparison).
     *
     * @see has_value_ci
     */
    public bool has_value_cs(string attribute, string value) {
        string? stored = params.get(attribute);

        return (stored != null) ? Ascii.str_equal(stored, value) : false;
    }

}
