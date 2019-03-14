/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A generic IMAP message or mailbox flag.
 *
 * In IMAP, message and mailbox flags have similar syntax, which is encapsulated here.
 *
 * @see MessageFlag
 * @see MailboxAttribute
 */

public abstract class Geary.Imap.Flag : BaseObject, Gee.Hashable<Geary.Imap.Flag> {
    public string value { get; private set; }

    /**
     * Constructs a new flag.
     *
     * The given keyword must be an IMAP atom.
     */
    protected Flag(string name) {
        this.value = name;
    }

    public bool is_system() {
        return value[0] == '\\';
    }

    public bool equals_string(string value) {
        return Ascii.stri_equal(this.value, value);
    }

    public bool equal_to(Geary.Imap.Flag flag) {
        return (flag == this) ? true : flag.equals_string(value);
    }

    /**
     * Returns the {@link Flag} as an appropriate {@link Parameter}.
     */
    public StringParameter to_parameter() throws ImapError {
        return new UnquotedStringParameter(value);
    }

    public uint hash() {
        return Ascii.stri_hash(value);
    }

    public string to_string() {
        return value;
    }
}



