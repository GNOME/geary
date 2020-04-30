/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

public class Geary.Imap.Capabilities : Geary.GenericCapabilities {


    public const string AUTH = "AUTH";
    public const string AUTH_XOAUTH2 = "XOAUTH2";
    public const string CREATE_SPECIAL_USE = "CREATE-SPECIAL-USE";
    public const string COMPRESS = "COMPRESS";
    public const string DEFLATE_SETTING = "DEFLATE";
    public const string IDLE = "IDLE";
    public const string IMAP4REV1 = "IMAP4rev1";
    public const string NAMESPACE = "NAMESPACE";
    public const string SPECIAL_USE = "SPECIAL-USE";
    public const string STARTTLS = "STARTTLS";
    public const string UIDPLUS = "UIDPLUS";
    public const string XLIST = "XLIST";

    public const string NAME_SEPARATOR = "=";
    public const string? VALUE_SEPARATOR = null;

    /**
     * The version of this set of capabilities for an IMAP session.
     *
     * The capabilities that an IMAP session offers changes over time,
     * for example after login or STARTTLS. This property supports
     * detecting these changes.
     *
     * @see ClientSession.capabilities
     */
    public int revision { get; private set; }


    /**
     * Creates an empty set of capabilities.
     */
    public Capabilities(StringParameter[] capabilities, int revision) {
        this.empty(revision);
        foreach (var cap in capabilities) {
            parse_and_add_capability(cap.ascii);
        }
    }

    /**
     * Creates an empty set of capabilities.
     */
    public Capabilities.empty(int revision) {
        base(NAME_SEPARATOR, VALUE_SEPARATOR);
        this.revision = revision;
    }

    public override string to_string() {
        return "#%d: %s".printf(revision, base.to_string());
    }

    /**
     * Indicates an IMAP session reported support for IMAP 4rev1.
     *
     * See [[https://tools.ietf.org/html/rfc2177]]
     */
    public bool supports_imap4rev1() {
        return has_capability(IMAP4REV1);
    }

    /**
     * Indicates the {@link ClientSession} reported support for IDLE.
     *
     * See [[https://tools.ietf.org/html/rfc2177]]
     */
    public bool supports_idle() {
        return has_capability(IDLE);
    }

    /**
     * Indicates the {@link ClientSession} reported support for UIDPLUS.
     *
     * See [[https://tools.ietf.org/html/rfc4315]]
     */
    public bool supports_uidplus() {
        return has_capability(UIDPLUS);
    }

    /**
     * Indicates the {@link ClientSession} reported support for SPECIAL-USE.
     *
     * See [[https://tools.ietf.org/html/rfc6154]]
     */
    public bool supports_special_use() {
        return has_capability(SPECIAL_USE);
    }
}

