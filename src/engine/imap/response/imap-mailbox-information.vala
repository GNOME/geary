/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * The decoded response to a LIST command.
 *
 * This is also the response to an XLIST command.
 *
 * See [[http://tools.ietf.org/html/rfc3501#section-7.2.2]]
 *
 * @see ListCommand
 */

public class Geary.Imap.MailboxInformation : BaseObject {
    /**
     * Name of the mailbox.
     */
    public MailboxSpecifier mailbox { get; private set; }

    /**
     * The (optional) delimiter specified by the server.
     */
    public string? delim { get; private set; }

    /**
     * Folder attributes returned by the server.
     */
    public MailboxAttributes attrs { get; private set; }

    public MailboxInformation(MailboxSpecifier mailbox, string? delim, MailboxAttributes attrs) {
        this.mailbox = mailbox;
        this.delim = delim;
        this.attrs = attrs;
    }

    /**
     * Decodes {@link ServerData} into a MailboxInformation representation.
     *
     * If canonical_inbox is true, the {@link MailboxAttributes} are searched for the \Inbox flag.
     * If found, {@link MailboxSpecifier.CANONICAL_INBOX_NAME} is used rather than the one returned
     * by the server.
     *
     * The ServerData must be the response to a LIST or XLIST command.
     *
     * @see ListCommand
     * @see ServerData.get_list
     */
    public static MailboxInformation decode(ServerData server_data, bool canonical_inbox) throws ImapError {
        StringParameter cmd = server_data.get_as_string(1);
        if (!cmd.equals_ci(ListCommand.NAME) && !cmd.equals_ci(ListCommand.XLIST_NAME))
            throw new ImapError.PARSE_ERROR("Not LIST or XLIST data: %s", server_data.to_string());

        // Build list of attributes
        ListParameter attrs = server_data.get_as_list(2);
        Gee.Collection<MailboxAttribute> attrlist = new Gee.ArrayList<MailboxAttribute>();
        foreach (Parameter attr in attrs.get_all()) {
            StringParameter? stringp = attr as StringParameter;
            if (stringp == null) {
                debug("Bad list attribute \"%s\": Attribute not a string value",
                    server_data.to_string());

                continue;
            }

            attrlist.add(new MailboxAttribute(stringp.ascii));
        }

        // decode everything
        MailboxAttributes attributes = new MailboxAttributes(attrlist);
        StringParameter? delim = server_data.get_as_nullable_string(3);
        StringParameter mailbox = server_data.get_as_string(4);

        // If special-use flag \Inbox is set just use the canonical
        // Inbox name, otherwise decode it
        MailboxSpecifier? specifier =
            (canonical_inbox &&
             Geary.Imap.MailboxAttribute.XLIST_INBOX in attributes)
            ? MailboxSpecifier.inbox
            : new MailboxSpecifier.from_parameter(mailbox);

        return new MailboxInformation(
            specifier, (delim != null) ? delim.nullable_ascii : null, attributes
        );
    }

    public string to_string() {
        return "%s/%s".printf(mailbox.to_string(), attrs.to_string());
    }

}
