/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * MessageData is an IMAP data structure delivered in some form by the server to the client.
 *
 * Note that IMAP specifies that Flags and Attributes are *always* returned as a list, even if only
 * one is present, which is why these elements are MessageData but not the elements within the
 * lists (Flag, Attribute).
 *
 * Also note that Imap.MessageData requires {@link Geary.MessageData.AbstractMessageData}.
 *
 * TODO: Add an abstract to_parameter() method that can be used to serialize the message data.
 */

public interface Geary.Imap.MessageData : Geary.MessageData.AbstractMessageData {
}

public class Geary.Imap.RFC822Size : Geary.MessageData.Int64MessageData, Geary.Imap.MessageData {
    public RFC822Size(int64 value) {
        base (value);
    }
}

public class Geary.Imap.RFC822Header : Geary.RFC822.Header, Geary.Imap.MessageData {
    public RFC822Header(Memory.Buffer buffer)
        throws ImapError {
        try {
            base(buffer);
        } catch (RFC822.Error error) {
            throw new ImapError.INVALID(error.message);
        }
    }
}

public class Geary.Imap.RFC822Text : Geary.RFC822.Text, Geary.Imap.MessageData {
    public RFC822Text(Memory.Buffer buffer) {
        base (buffer);
    }
}

public class Geary.Imap.RFC822Full : Geary.RFC822.Full, Geary.Imap.MessageData {
    public RFC822Full(Memory.Buffer buffer) {
        base (buffer);
    }
}
