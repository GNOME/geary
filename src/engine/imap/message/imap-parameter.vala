/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public abstract class Geary.Imap.Parameter : BaseObject, Serializable {
    public abstract async void serialize(Serializer ser) throws Error;
    
    /**
     * to_string() returns a representation of the Parameter suitable for logging and debugging,
     * but should not be relied upon for wire or persistent representation.
     */
    public abstract string to_string();
}

public class Geary.Imap.NilParameter : Geary.Imap.Parameter {
    public const string VALUE = "NIL";
    
    private static NilParameter? _instance = null;
    
    public static NilParameter instance {
        get {
             if (_instance == null)
                _instance = new NilParameter();
            
            return _instance;
        }
    }
    
    private NilParameter() {
    }
    
    public static bool is_nil(string str) {
        return String.ascii_equali(VALUE, str);
    }
    
    public override async void serialize(Serializer ser) throws Error {
        ser.push_nil();
    }
    
    public override string to_string() {
        return VALUE;
    }
}

public class Geary.Imap.StringParameter : Geary.Imap.Parameter {
    public string value { get; private set; }
    public string? nullable_value {
        get {
            return String.is_empty(value) ? null : value;
        }
    }
    
    public StringParameter(string value) {
        this.value = value;
    }
    
    public bool equals_cs(string value) {
        return this.value == value;
    }
    
    public bool equals_ci(string value) {
        return this.value.down() == value.down();
    }
    
    // TODO: This does not check that the value is a properly-formed integer.  This should be
    // added later.
    public int as_int(int clamp_min = int.MIN, int clamp_max = int.MAX) throws ImapError {
        return int.parse(value).clamp(clamp_min, clamp_max);
    }
    
    // TODO: This does not check that the value is a properly-formed long.
    public long as_long(int clamp_min = int.MIN, int clamp_max = int.MAX) throws ImapError {
        return long.parse(value).clamp(clamp_min, clamp_max);
    }
    
    // TODO: This does not check that the value is a properly-formed int64.
    public int64 as_int64(int64 clamp_min = int64.MIN, int64 clamp_max = int64.MAX) throws ImapError {
        return int64.parse(value).clamp(clamp_min, clamp_max);
    }
    
    public override string to_string() {
        return value;
    }
    
    public override async void serialize(Serializer ser) throws Error {
        ser.push_string(value);
    }
}

/**
 * This delivers the string to the IMAP server with quoting applied whether or not it's required.
 * (Deserializer will never generate this Parameter.)  This is generally legal, but some servers may
 * not appreciate it.
 */
public class Geary.Imap.QuotedStringParameter : Geary.Imap.StringParameter {
    public QuotedStringParameter(string value) {
        base (value);
    }
    
    public override async void serialize(Serializer ser) throws Error {
        ser.push_quoted_string(value);
    }
}

/**
 * This delivers the string to the IMAP server with no quoting or formatting applied.  (Deserializer
 * will never generate this Parameter.)  This can lead to server errors if misused.  Use only if
 * absolutely necessary.
 */
public class Geary.Imap.UnquotedStringParameter : Geary.Imap.StringParameter {
    public UnquotedStringParameter(string value) {
        base (value);
    }
    
    public override async void serialize(Serializer ser) throws Error {
        ser.push_unquoted_string(value);
    }
}

public class Geary.Imap.LiteralParameter : Geary.Imap.Parameter {
    private Geary.Memory.AbstractBuffer buffer;
    
    public LiteralParameter(Geary.Memory.AbstractBuffer buffer) {
        this.buffer = buffer;
    }
    
    public size_t get_size() {
        return buffer.get_size();
    }
    
    public Geary.Memory.AbstractBuffer get_buffer() {
        return buffer;
    }
    
    /**
     * Returns the LiteralParameter as though it had been a StringParameter on the wire.  Note
     * that this does not deal with quoting issues or NIL (which should never be literalized to
     * begin with).  It merely converts the literal data to a UTF-8 string and returns it as a
     * StringParameter.
     */
    public StringParameter to_string_parameter() {
        return new StringParameter(buffer.to_valid_utf8());
    }
    
    public override string to_string() {
        return "{literal/%lub}".printf(get_size());
    }
    
    public override async void serialize(Serializer ser) throws Error {
        ser.push_string("{%lu}".printf(get_size()));
        ser.push_eol();
        yield ser.push_input_stream_literal_data_async(buffer.get_input_stream());
    }
}

public class Geary.Imap.ListParameter : Geary.Imap.Parameter {
    /**
     * The maximum length a literal parameter may be to be auto-converted to a StringParameter
     * in the StringParameter getters.
     */
    public const int MAX_STRING_LITERAL_LENGTH = 4096;
    
    private weak ListParameter? parent;
    private Gee.List<Parameter> list = new Gee.ArrayList<Parameter>();
    
    public ListParameter(ListParameter? parent, Parameter? initial = null) {
        this.parent = parent;
        
        if (initial != null)
            add(initial);
    }
    
    public ListParameter? get_parent() {
        return parent;
    }
    
    public void add(Parameter param) {
        bool added = list.add(param);
        assert(added);
    }
    
    public int get_count() {
        return list.size;
    }
    
    /**
     * Returns the Parameter at the index in the list, null if index is out of range.
     *
     * TODO: This call can cause memory leaks when used with the "as" operator until the following
     * Vala bug is fixed (probably in version 0.19.1).
     * https://bugzilla.gnome.org/show_bug.cgi?id=695671
     */
    public new Parameter? get(int index) {
        return ((index >= 0) && (index < list.size)) ? list.get(index) : null;
    }
    
    /**
     * Returns the Parameter at the index.  Throws an ImapError.TYPE_ERROR if the index is out of
     * range.
     *
     * TODO: This call can cause memory leaks when used with the "as" operator until the following
     * Vala bug is fixed (probably in version 0.19.1).
     * https://bugzilla.gnome.org/show_bug.cgi?id=695671
     */
    public Parameter get_required(int index) throws ImapError {
        if ((index < 0) || (index >= list.size))
            throw new ImapError.TYPE_ERROR("No parameter at index %d", index);
        
        Parameter? param = list.get(index);
        if (param == null)
            throw new ImapError.TYPE_ERROR("No parameter at index %d", index);
        
        return param;
    }
    
    /**
     * Returns Paramater at index if in range and of Type type, otherwise throws an
     * ImapError.TYPE_ERROR.  type must be of type Parameter.
     */
    public Parameter get_as(int index, Type type) throws ImapError {
        assert(type.is_a(typeof(Parameter)));
        
        Parameter param = get_required(index);
        if (!param.get_type().is_a(type)) {
            throw new ImapError.TYPE_ERROR("Parameter %d is not of type %s (is %s)", index,
                type.name(), param.get_type().name());
        }
        
        return param;
    }
    
    /**
     * Like get_as(), but returns null if the Parameter at index is a NilParameter.
     */
    public Parameter? get_as_nullable(int index, Type type) throws ImapError {
        assert(type.is_a(typeof(Parameter)));
        
        Parameter param = get_required(index);
        if (param is NilParameter)
            return null;
        
        if (!param.get_type().is_a(type)) {
            throw new ImapError.TYPE_ERROR("Parameter %d is not of type %s (is %s)", index,
                type.name(), param.get_type().name());
        }
        
        return param;
    }
    
    /**
     * Like get(), but returns null if Parameter at index is not of the specified type.  type must
     * be of type Parameter.
     */
    public Parameter? get_if(int index, Type type) {
        assert(type.is_a(typeof(Parameter)));
        
        Parameter? param = get(index);
        if (param == null || !param.get_type().is_a(type))
            return null;
        
        return param;
    }
    
    /**
     * Returns a StringParameter only if the Parameter at index is a StringParameter (quoted or
     * atom string).
     */
    public StringParameter get_only_as_string(int index) throws ImapError {
        return (StringParameter) get_as(index, typeof(StringParameter));
    }
    
    /**
     * Returns a StringParameter only if the Parameter at index is a StringParameter (quoted or
     * atom string).
     */
    public StringParameter? get_only_as_nullable_string(int index) throws ImapError {
        return (StringParameter?) get_as_nullable(index, typeof(StringParameter));
    }
    
    /**
     * Returns a StringParameter only if the Parameter at index is a StringParameter (quoted or
     * atom string).  Returns an empty StringParameter if index is for a NilParameter;
     */
    public StringParameter get_only_as_empty_string(int index) throws ImapError {
        StringParameter? param = get_only_as_nullable_string(index);
        
        return param ?? new StringParameter("");
    }
    
    /**
     * Returns a StringParameter only if the Parameter at index is a StringParameter (quoted or
     * atom string).
     */
    public StringParameter? get_only_if_string(int index) {
        return (StringParameter?) get_if(index, typeof(StringParameter));
    }
    
    /**
     * Returns the StringParameter at the index only if the Parameter is a StringParameter or a
     * LiteralParameter with a length less than or equal to MAX_STRING_LITERAL_LENGTH.  Throws an
     * ImapError.TYPE_ERROR if a literal longer than that value.
     */
    public StringParameter get_as_string(int index) throws ImapError {
        Parameter param = get_required(index);
        
        StringParameter? stringp = param as StringParameter;
        if (stringp != null)
            return stringp;
        
        LiteralParameter? literalp = param as LiteralParameter;
        if (literalp != null && literalp.get_size() <= MAX_STRING_LITERAL_LENGTH)
            return literalp.to_string_parameter();
        
        throw new ImapError.TYPE_ERROR("Parameter %d not of type string or literal (is %s)", index,
            param.get_type().name());
    }
    
    /**
     * Much like get_nullable() for StringParameters, but will convert a LiteralParameter to a
     * StringParameter if its length is less than or equal to MAX_STRING_LITERAL_LENGTH.  Throws
     * an ImapError.TYPE_ERROR if literal is longer than that value.
     */
    public StringParameter? get_as_nullable_string(int index) throws ImapError {
        Parameter? param = get_as_nullable(index, typeof(Parameter));
        if (param == null)
            return null;
        
        StringParameter? stringp = param as StringParameter;
        if (stringp != null)
            return stringp;
        
        LiteralParameter? literalp = param as LiteralParameter;
        if (literalp != null && literalp.get_size() <= MAX_STRING_LITERAL_LENGTH)
            return literalp.to_string_parameter();
        
        throw new ImapError.TYPE_ERROR("Parameter %d not of type string or literal (is %s)", index,
            param.get_type().name());
    }
    
    /**
     * Much like get_as_nullable_string() but returns an empty StringParameter (rather than null)
     * if the parameter at index is a NilParameter.
     */
    public StringParameter get_as_empty_string(int index) throws ImapError {
        StringParameter? stringp = get_as_nullable_string(index);
        
        return stringp ?? new StringParameter("");
    }
    
    /**
     * Returns the StringParameter at the index only if the Parameter is a StringParameter or a
     * LiteralParameter with a length less than or equal to MAX_STRING_LITERAL_LENGTH.  Returns null
     * if either is not true.
     */
    public StringParameter? get_if_string(int index) {
        Parameter? param = get(index);
        if (param == null)
            return null;
        
        StringParameter? stringp = param as StringParameter;
        if (stringp != null)
            return stringp;
        
        LiteralParameter? literalp = param as LiteralParameter;
        if (literalp != null && literalp.get_size() <= MAX_STRING_LITERAL_LENGTH)
            return literalp.to_string_parameter();
        
        return null;
    }
    
    public ListParameter get_as_list(int index) throws ImapError {
        return (ListParameter) get_as(index, typeof(ListParameter));
    }
    
    public ListParameter? get_as_nullable_list(int index) throws ImapError {
        return (ListParameter?) get_as_nullable(index, typeof(ListParameter));
    }
    
    public ListParameter get_as_empty_list(int index) throws ImapError {
        ListParameter? param = get_as_nullable_list(index);
        
        return param ?? new ListParameter(this);
    }
    
    public ListParameter? get_if_list(int index) {
        return (ListParameter?) get_if(index, typeof(ListParameter));
    }
    
    public LiteralParameter get_as_literal(int index) throws ImapError {
        return (LiteralParameter) get_as(index, typeof(LiteralParameter));
    }
    
    public LiteralParameter? get_as_nullable_literal(int index) throws ImapError {
        return (LiteralParameter?) get_as_nullable(index, typeof(LiteralParameter));
    }
    
    public LiteralParameter? get_if_literal(int index) {
        return (LiteralParameter?) get_if(index, typeof(LiteralParameter));
    }
    
    public LiteralParameter get_as_empty_literal(int index) throws ImapError {
        LiteralParameter? param = get_as_nullable_literal(index);
        
        return param ?? new LiteralParameter(Geary.Memory.EmptyBuffer.instance);
    }
    
    public Gee.List<Parameter> get_all() {
        return list.read_only_view;
    }
    
    /**
     * Returns the replaced Paramater.  Throws ImapError.TYPE_ERROR if no Parameter exists at the
     * index.
     */
    public Parameter replace(int index, Parameter parameter) throws ImapError {
        if (list.size <= index)
            throw new ImapError.TYPE_ERROR("No parameter at index %d", index);
        
        Parameter old = list[index];
        list[index] = parameter;
        
        return old;
    }
    
    /**
     * Moves all child parameters from the supplied list into this list.  The supplied list will be
     * "stripped" of children.
     */
    public void move_children(ListParameter src) {
        list.clear();
        
        foreach (Parameter param in src.list) {
            ListParameter? listp = param as ListParameter;
            if (listp != null)
                listp.parent = this;
            
            list.add(param);
        }
        
        src.list.clear();
    }
    
    protected string stringize_list() {
        StringBuilder builder = new StringBuilder();
        
        int length = list.size;
        for (int ctr = 0; ctr < length; ctr++) {
            builder.append(list[ctr].to_string());
            if (ctr < (length - 1))
                builder.append_c(' ');
        }
        
        return builder.str;
    }
    
    public override string to_string() {
        return "(%s)".printf(stringize_list());
    }
    
    protected async void serialize_list(Serializer ser) throws Error {
        int length = list.size;
        for (int ctr = 0; ctr < length; ctr++) {
            yield list[ctr].serialize(ser);
            if (ctr < (length - 1))
                ser.push_space();
        }
    }
    
    public override async void serialize(Serializer ser) throws Error {
        ser.push_ascii('(');
        yield serialize_list(ser);
        ser.push_ascii(')');
    }
}

public class Geary.Imap.RootParameters : Geary.Imap.ListParameter {
    public RootParameters(Parameter? initial = null) {
        base (null, initial);
    }
    
    public RootParameters.migrate(RootParameters root) {
        base (null);
        
        move_children(root);
    }
    
    public override string to_string() {
        return stringize_list();
    }
    
    public override async void serialize(Serializer ser) throws Error {
        yield serialize_list(ser);
        ser.push_eol();
    }
}

