/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * The decoded response to a STATUS command.
 *
 * See [[http://tools.ietf.org/html/rfc3501#section-7.2.4]]
 *
 * @see StatusCommand
 */

public class Geary.Imap.StatusData : Object {
    // NOTE: This must be negative one; other values won't work well due to how the values are
    // decoded
    public const int UNSET = -1;

    /**
     * Name of the mailbox.
     */
    public MailboxSpecifier mailbox { get; private set; }

    /**
     * {@link UNSET} if not set.
     */
    public int messages { get; private set; }

    /**
     * {@link UNSET} if not set.
     */
    public int recent { get; private set; }

    /**
     * The UIDNEXT of the mailbox, if returned.
     *
     * See [[http://tools.ietf.org/html/rfc3501#section-2.3.1.1]]
     */
    public UID? uid_next { get; private set; }

    /**
     * The UIDVALIDITY of the mailbox, if returned.
     *
     * See [[http://tools.ietf.org/html/rfc3501#section-2.3.1.1]]
     */
    public UIDValidity? uid_validity { get; private set; }

    /**
     * {@link UNSET} if not set.
     */
    public int unseen { get; private set; }

    public StatusData(MailboxSpecifier mailbox, int messages, int recent, UID? uid_next,
        UIDValidity? uid_validity, int unseen) {
        this.mailbox = mailbox;
        this.messages = messages;
        this.recent = recent;
        this.uid_next = uid_next;
        this.uid_validity = uid_validity;
        this.unseen = unseen;
    }

    /**
     * Decodes {@link ServerData} into a StatusData representation.
     *
     * The ServerData must be the response to a STATUS command.
     *
     * @see StatusCommand
     * @see ServerData.get_status
     */
    public static StatusData decode(ServerData server_data) throws ImapError {
        if (!server_data.get_as_string(1).equals_ci(StatusCommand.NAME)) {
            throw new ImapError.PARSE_ERROR("Bad STATUS command name in response \"%s\"",
                server_data.to_string());
        }

        StringParameter mailbox_param = server_data.get_as_string(2);

        int messages = UNSET;
        int recent = UNSET;
        UID? uid_next = null;
        UIDValidity? uid_validity = null;
        int unseen = UNSET;

        ListParameter values = server_data.get_as_list(3);
        for (int ctr = 0; ctr < values.size; ctr += 2) {
            try {
                StringParameter typep = values.get_as_string(ctr);
                StringParameter valuep = values.get_as_string(ctr + 1);

                switch (StatusDataType.from_parameter(typep)) {
                    case StatusDataType.MESSAGES:
                        // see note at UNSET
                        messages = valuep.as_int32(-1, int.MAX);
                    break;

                    case StatusDataType.RECENT:
                        // see note at UNSET
                        recent = valuep.as_int32(-1, int.MAX);
                    break;

                    case StatusDataType.UIDNEXT:
                        try {
                            uid_next = new UID.checked(valuep.as_int64());
                        } catch (ImapError.INVALID err) {
                            // Some mail servers e.g hMailServer and
                            // whatever is used by home.pl (dovecot?)
                            // sends UIDNEXT 0. Just ignore these
                            // since there nothing else that can be
                            // done. See GNOME/geary#711
                            if (valuep.as_int64() == 0) {
                                warning("Ignoring bad UIDNEXT 0 from server");
                            } else {
                                throw err;
                            }
                        }
                    break;

                    case StatusDataType.UIDVALIDITY:
                        uid_validity = new UIDValidity.checked(valuep.as_int64());
                    break;

                    case StatusDataType.UNSEEN:
                        // see note at UNSET
                        unseen = valuep.as_int32(-1, int.MAX);
                    break;

                    default:
                        message("Bad STATUS data type %s", typep.to_string());
                    break;
                }
            } catch (ImapError ierr) {
                warning(
                    "Bad value at %d/%d in STATUS response \"%s\": %s",
                    ctr, ctr + 1, server_data.to_string(), ierr.message
                );
            }
        }

        return new StatusData(new MailboxSpecifier.from_parameter(mailbox_param), messages, recent,
            uid_next, uid_validity, unseen);
    }

    public string to_string() {
        return "%s/%d/UIDNEXT=%s/UIDVALIDITY=%s".printf(mailbox.to_string(), messages,
            (uid_next != null) ? uid_next.to_string() : "(none)",
            (uid_validity != null) ? uid_validity.to_string() : "(none)");
    }
}

