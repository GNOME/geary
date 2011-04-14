/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public abstract class Geary.Imap.Parameter : Object, Serializable {
    public abstract void serialize(Serializer ser) throws Error;
    
    // to_string() returns a representation of the Parameter suitable for logging and debugging,
    // but should not be relied upon for wire or persistent representation.
    public abstract string to_string();
}

public class Geary.Imap.StringParameter : Geary.Imap.Parameter {
    public string value { get; private set; }
    
    public StringParameter(string value) requires (!is_empty_string(value)) {
        this.value = value;
    }
    
    public StringParameter.NIL() {
        this.value = "nil";
    }
    
    public bool is_nil() {
        return value.down() == "nil";
    }
    
    public override string to_string() {
        return value;
    }
    
    public override void serialize(Serializer ser) throws Error {
        ser.push_string(value);
    }
}

public class Geary.Imap.LiteralParameter : Geary.Imap.Parameter {
    private MemoryInputStream mins = new MemoryInputStream();
    private long size = 0;
    
    public LiteralParameter(uint8[]? initial = null) {
        if (initial != null)
            add(initial);
    }
    
    public void add(uint8[] data) {
        if (data.length == 0)
            return;
        
        mins.add_data(data, null);
        size += data.length;
    }
    
    public long get_size() {
        return size;
    }
    
    public override string to_string() {
        return "{literal/%ldb}".printf(size);
    }
    
    public override void serialize(Serializer ser) throws Error {
        ser.push_string("{%ld}".printf(size));
        ser.push_eol();
        ser.push_input_stream_literal_data(mins);
        
        // seek to start
        mins.seek(0, SeekType.SET);
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
    
    public Parameter get_as(int index, Type type) throws ImapError {
        assert(type.is_a(typeof(Parameter)));
        
        if (index >= list.size)
            throw new ImapError.TYPE_ERROR("No parameter at index %d", index);
        
        Parameter param = list.get(index);
        if (!param.get_type().is_a(type))
            throw new ImapError.TYPE_ERROR("Parameter %d is not of type %s", index, type.name());
        
        return param;
    }
    
    public Gee.List<Parameter> get_all() {
        return list.read_only_view;
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
    
    protected void serialize_list(Serializer ser) throws Error {
        int length = list.size;
        for (int ctr = 0; ctr < length; ctr++) {
            list[ctr].serialize(ser);
            if (ctr < (length - 1))
                ser.push_space();
        }
    }
    
    public override void serialize(Serializer ser) throws Error {
        ser.push_string("(");
        serialize_list(ser);
        ser.push_string(")");
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
    
    public override void serialize(Serializer ser) throws Error {
        serialize_list(ser);
        ser.push_eol();
    }
}

