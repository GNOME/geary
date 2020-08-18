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



    public void update_for_server(ClientSession session) {
        if (session.server_greeting != null) {
            var greeting = session.server_greeting.get_text() ?? "";
            if (greeting.has_prefix("Gimap")) {
                update_for_gmail();
            } else if (greeting.has_prefix("The Microsoft Exchange")) {
                update_for_outlook();
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

}
