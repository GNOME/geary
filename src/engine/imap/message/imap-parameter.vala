/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public abstract class Geary.Imap.Parameter : Object, Serializable {
    public abstract async void serialize(Serializer ser) throws Error;
    
    // to_string() returns a representation of the Parameter suitable for logging and debugging,
    // but should not be relied upon for wire or persistent representation.
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
    
    public new Parameter? get(int index) {
        return list.get(index);
    }
    
    public Parameter get_required(int index) throws ImapError {
        Parameter? param = list.get(index);
        if (param == null)
            throw new ImapError.TYPE_ERROR("No parameter at index %d", index);
        
        return param;
    }
    
    public Parameter get_as(int index, Type type) throws ImapError {
        assert(type.is_a(typeof(Parameter)));
        
        Parameter param = get_required(index);
        if (!param.get_type().is_a(type)) {
            throw new ImapError.TYPE_ERROR("Parameter %d is not of type %s (is %s)", index,
                type.name(), param.get_type().name());
        }
        
        return param;
    }
    
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
    
    public StringParameter get_as_string(int index) throws ImapError {
        return (StringParameter) get_as(index, typeof(StringParameter));
    }
    
    public StringParameter? get_as_nullable_string(int index) throws ImapError {
        return (StringParameter?) get_as_nullable(index, typeof(StringParameter));
    }
    
    public StringParameter get_as_empty_string(int index) throws ImapError {
        StringParameter? param = get_as_nullable_string(index);
        
        return param ?? new StringParameter("");
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
    
    public LiteralParameter get_as_literal(int index) throws ImapError {
        return (LiteralParameter) get_as(index, typeof(LiteralParameter));
    }
    
    public LiteralParameter? get_as_nullable_literal(int index) throws ImapError {
        return (LiteralParameter?) get_as_nullable(index, typeof(LiteralParameter));
    }
    
    public LiteralParameter get_as_empty_parameter(int index) throws ImapError {
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
    
    // This replaces all existing parameters with those from the supplied list
    public void copy(ListParameter src) {
        list.clear();
        list.add_all(src.get_all());
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
    
    public RootParameters.clone(RootParameters root) {
        base (null);
        
        base.copy(root);
    }
    
    public override string to_string() {
        return stringize_list();
    }
    
    public override async void serialize(Serializer ser) throws Error {
        yield serialize_list(ser);
        ser.push_eol();
    }
}

