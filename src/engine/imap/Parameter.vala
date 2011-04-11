/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public abstract class Geary.Imap.Parameter : Serializable {
    public abstract void serialize(Serializer ser) throws Error;
    
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
    
    public Gee.List<Parameter> get_all() {
        return list.read_only_view;
    }
    
    /*
    public Parameter? get_next(ref int index, Type type, bool optional) throws ImapError {
        assert(type.is_a(Parameter));
        
        if (index >= list.size) {
            if (!optional)
                throw new ImapError.PARSE_ERROR;
            
            return null;
        }
        
        Parameter param = list.get(index);
        if (!(typeof(param).is_a(type)) {
            if (!optional)
                throw new ImapError.PARSE_ERROR;
            
            return null;
        }
        
        index++;
        
        return param;
    }
    */
    
    protected string stringize_list() {
        string str = "";
        
        int length = list.size;
        for (int ctr = 0; ctr < length; ctr++) {
            str += list[ctr].to_string();
            if (ctr < (length - 1))
                str += " ";
        }
        
        return str;
    }
    
    public override string to_string() {
        return "%d:(%s)".printf(list.size, stringize_list());
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
    
    /*
    public bool is_status_response() {
        if (get_count() < 2)
            return false;
        
        StringParameter? strparam = get_all().get(1) as StringParameter;
        if (strparam == null)
            return false;
        
        try {
            Status.decode(strparam.value);
        } catch (Error err) {
            return false;
        }
        
        return true;
    }
    */
    
    public override string to_string() {
        return stringize_list();
    }
    
    public override void serialize(Serializer ser) throws Error {
        serialize_list(ser);
        ser.push_eol();
    }
}

