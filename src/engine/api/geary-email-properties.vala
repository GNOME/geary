/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * EmailProperties holds (in general) immutable metadata about an Email.  EmailFlags used to be
 * held here and retrieved via Email.Field.PROPERTIES, but as they're mutable, they were broken out
 * for efficiency reasons.
 *
 * EmailProperties may be expanded in the future to supply details like when the message was added
 * to the local store, checksums, and so forth.
 */

public abstract class Geary.EmailProperties : BaseObject {
    /**
     * date_received may be the date/time received on the server or in the local store, depending
     * on whether the information is available on the server.  For example, with IMAP, this is
     * the INTERNALDATE supplied by the server.
     */
    public DateTime date_received { get; protected set; }

    /**
     * Total size of the email (header and body) in bytes.
     */
    public int64 total_bytes { get; protected set; }

    protected EmailProperties(DateTime date_received, int64 total_bytes) {
        this.date_received = date_received;
        this.total_bytes = total_bytes;
    }

    public abstract string to_string();
}

