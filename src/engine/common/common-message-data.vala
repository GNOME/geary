/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * AbstractData is an abstract base class to unify the various message-related data and
 * metadata that may be associated with a mail message, whether it's embedded in its MIME
 * structure, its RFC822 header, IMAP metadata, details from a POP server, etc.
 */

public abstract class Geary.MessageData.AbstractMessageData : BaseObject {
    /**
     * to_string() is intended for debugging and logging purposes, not user-visible text or
     * serialization.
     */
    public abstract string to_string();
}

/**
 * Allows message data fields to define how they'll expose themselves to search
 * queries.
 */
public interface Geary.MessageData.SearchableMessageData {
    /**
     * Return a string representing the data as a corpus of text to be searched
     * against.  Return values from this may be stored in the search index.
     */
    public abstract string to_searchable_string();
}

public abstract class Geary.MessageData.StringMessageData : AbstractMessageData,
    Gee.Hashable<StringMessageData> {
    public string value { get; private set; }

    private uint stored_hash = uint.MAX;

    protected StringMessageData(string value) {
        this.value = value;
    }

    /**
     * Default definition of equals is case-sensitive comparison.
     */
    public virtual bool equal_to(StringMessageData other) {
        if (this == other)
            return true;

        if (hash() != other.hash())
            return false;

        return (value == other.value);
    }

    public virtual uint hash() {
        return (stored_hash != uint.MAX) ? stored_hash : (stored_hash = str_hash(value));
    }

    public override string to_string() {
        return value;
    }
}

public abstract class Geary.MessageData.IntMessageData : AbstractMessageData,
    Gee.Hashable<IntMessageData> {
    public int value { get; private set; }

    protected IntMessageData(int value) {
        this.value = value;
    }

    public virtual bool equal_to(IntMessageData other) {
        return (value == other.value);
    }

    public virtual uint hash() {
        return value;
    }

    public override string to_string() {
        return value.to_string();
    }
}

public abstract class Geary.MessageData.Int64MessageData : AbstractMessageData,
    Gee.Hashable<Int64MessageData> {
    public int64 value { get; private set; }

    private uint stored_hash = uint.MAX;

    protected Int64MessageData(int64 value) {
        this.value = value;
    }

    public virtual bool equal_to(Int64MessageData other) {
        if (this == other)
            return true;

        return (value == other.value);
    }

    public virtual uint hash() {
        return (stored_hash != uint.MAX) ? stored_hash : (stored_hash = int64_hash(value));
    }

    public override string to_string() {
        return value.to_string();
    }
}

public abstract class Geary.MessageData.BlockMessageData : AbstractMessageData {
    public string data_name { get; private set; }
    public Geary.Memory.Buffer buffer { get; private set; }

    protected BlockMessageData(string data_name, Geary.Memory.Buffer buffer) {
        this.data_name = data_name;
        this.buffer = buffer;
    }

    public override string to_string() {
        return "%s (%lub)".printf(data_name, buffer.size);
    }
}

