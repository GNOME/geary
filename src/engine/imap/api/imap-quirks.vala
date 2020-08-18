/*
 * Copyright © 2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * A set of quirks for a specific IMAP service.
 */
public class Geary.Imap.Quirks : BaseObject {


    /**
     * Whether spaces are disallowed in header parts of fetch commands.
     *
     * If true, HEADER parts of a BODY section may not contain any
     * spaces.
     *
     * E.g. this conformant form is not supported:
     *
     *     a008 UID FETCH * BODY.PEEK[HEADER.FIELDS (REFERENCES)]
     *
     * Whereas this non-conformant form is supported:
     *
     *     a008 UID FETCH * BODY.PEEK[HEADER.FIELDS(REFERENCES)]
     */
    public bool fetch_header_part_no_space { get; set; default = false; }

    /** The set of additional characters allowed in an IMAP flag. */
    public string? flag_atom_exceptions { get; set; }

    /**
     * The maximum number of commands that will be pipelined at once.
     *
     * If 0 (the default), there is no limit on the number of
     * pipelined commands sent to this endpoint.
     */
    public uint max_pipeline_batch_size { get; set; default = 0; }

    /**
     * The value sent by the server for missing envelope mailbox local parts.
     *
     * IMAP FETCH ENVELOPE structures use NIL for the "mailbox name"
     * part (in addition to a NIL "host name" part) as an end-of-list
     * marker for RFC822 group syntax. To indicate a missing
     * local-part in a non-group mailbox some mail servers use a
     * string such as "MISSING_MAILBOX" rather than the empty string.
     */
    public string empty_envelope_mailbox_name { get; set; default = ""; }

    /**
     * The value sent by the server for missing envelope mailbox domains.
     *
     * IMAP FETCH ENVELOPE structures use NIL for the "host name"
     * argument to indicate RFC822 group syntax. To indicate a missing
     * some mail servers use a string such as "MISSING_DOMAIN" rather
     * than the empty string.
     */
    public string empty_envelope_host_name { get; set; default = ""; }


    public void update_for_server(ClientSession session) {
        if (session.server_greeting != null) {
            var greeting = session.server_greeting.get_text() ?? "";
            if (greeting.has_prefix("Gimap")) {
                update_for_gmail();
            } else if (greeting.has_prefix("The Microsoft Exchange")) {
                update_for_outlook();
            } else if (greeting.has_prefix("Dovecot")) {
                update_for_dovecot();
            }
        }
    }

    /**
     * Updates this quirks object with known quirks for GMail.
     *
     * As of 2020-05-02, GMail doesn't seem to quote flag
     * atoms containing reserved characters, and at least one
     * use of both `]` and ` ` have been found. This works
     * around the former.
     *
     * See [[https://gitlab.gnome.org/GNOME/geary/-/issues/746]]
     */
    public void update_for_gmail() {
        this.flag_atom_exceptions = "]";
    }

    /**
     * Updates this quirks object with known quirks for Outlook.com.
     *
     * As of June 2016, outlook.com's IMAP servers have a bug where a
     * large number (~50) of pipelined STATUS commands on mailboxes
     * with many messages will eventually cause it to break command
     * parsing and return a BAD response, causing us to drop the
     * connection. Limit the number of pipelined commands per batch to
     * work around this.
     *
     * See [[https://bugzilla.gnome.org/show_bug.cgi?id=766552]]
     */
    public void update_for_outlook() {
        this.max_pipeline_batch_size = 25;
    }

    /**
     * Updates this quirks object with known quirks for Dovecot
     *
     * Dovecot 2.3.4.1 and earlier uses "MISSING_MAILBOX" and
     * "MISSING_DOMAIN" in the address structures of FETCH ENVELOPE
     * replies when the mailbox or domain is missing.
     *
     * See [[https://dovecot.org/pipermail/dovecot/2020-August/119658.html]]
     */
    public void update_for_dovecot() {
        this.empty_envelope_mailbox_name = "MISSING_MAILBOX";
        this.empty_envelope_host_name = "MISSING_DOMAIN";
    }

}
