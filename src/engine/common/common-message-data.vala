/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

/**
 * Common.MessageData is an abstract base class to unify the various message-related data and
 * metadata that may be associated with a mail message, whether it's embedded in its MIME
 * structure, its RFC822 header, IMAP metadata, or details from a POP server.
 */

public abstract class Geary.Common.MessageData {
    /**
     * to_string() is intended for debugging and logging purposes, not user-visible text or
     * serialization.
     */
    public abstract string to_string();
}

public abstract class Geary.Common.StringMessageData : Geary.Common.MessageData, Hashable, Equalable {
    public string value { get; private set; }
    
    private uint hash = uint.MAX;
    
    public StringMessageData(string value) {
        this.value = value;
    }
    
    /**
     * Default definition of equals is case-sensitive comparison.
     */
    public virtual bool equals(Equalable e) {
        StringMessageData? other = e as StringMessageData;
        if (other == null)
            return false;
        
        if (this == other)
            return true;
        
        if (to_hash() != other.to_hash())
            return false;
        
        return (value == other.value);
    }
    
    public virtual uint to_hash() {
        return (hash != uint.MAX) ? hash : (hash = str_hash(value));
    }
    
    public override string to_string() {
        return value;
    }
}

public abstract class Geary.Common.IntMessageData : Geary.Common.MessageData, Hashable, Equalable {
    public int value { get; private set; }
    
    public IntMessageData(int value) {
        this.value = value;
    }
    
    public virtual bool equals(Equalable e) {
        IntMessageData? other = e as IntMessageData;
        if (other == null)
            return false;
        
        if (this == other)
            return true;
        
        return (value == other.value);
    }
    
    public virtual uint to_hash() {
        return int_hash(value);
    }
    
    public override string to_string() {
        return value.to_string();
    }
}

public abstract class Geary.Common.LongMessageData : Geary.Common.MessageData, Hashable, Equalable {
    public long value { get; private set; }
    
    public LongMessageData(long value) {
        this.value = value;
    }
    
    public virtual bool equals(Equalable e) {
        LongMessageData? other = e as LongMessageData;
        if (other == null)
            return false;
        
        if (this == other)
            return true;
        
        return (value == other.value);
    }
    
    public virtual uint to_hash() {
        return int64_hash((int64) value);
    }
    
    public override string to_string() {
        return value.to_string();
    }
}

public abstract class Geary.Common.Int64MessageData : Geary.Common.MessageData, Hashable, Equalable {
    public int64 value { get; private set; }
    
    public Int64MessageData(int64 value) {
        this.value = value;
    }
    
    public virtual bool equals(Equalable e) {
        Int64MessageData? other = e as Int64MessageData;
        if (other == null)
            return false;
        
        if (this == other)
            return true;
        
        return (value == other.value);
    }
    
    public virtual uint to_hash() {
        return int64_hash(value);
    }
    
    public override string to_string() {
        return value.to_string();
    }
}

public abstract class Geary.Common.BlockMessageData : Geary.Common.MessageData {
    public string data_name { get; private set; }
    public Geary.Memory.AbstractBuffer buffer { get; private set; }
    
    public BlockMessageData(string data_name, Geary.Memory.AbstractBuffer buffer) {
        this.data_name = data_name;
        this.buffer = buffer;
    }
    
    public override string to_string() {
        return "%s (%lub)".printf(data_name, buffer.get_size());
    }
}

