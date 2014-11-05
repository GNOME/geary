/* Copyright 2011-2012 Yorba Foundation
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
        MailboxParameter mailbox = new MailboxParameter.from_string_parameter(
            server_data.get_as_string(4));
        
        // Set \Inbox to standard path
        if (canonical_inbox && Geary.Imap.MailboxAttribute.SPECIAL_FOLDER_INBOX in attributes) {
            return new MailboxInformation(MailboxSpecifier.inbox,
                (delim != null) ? delim.nullable_ascii : null, attributes);
        } else {
            return new MailboxInformation(new MailboxSpecifier.from_parameter(mailbox),
                (delim != null) ? delim.nullable_ascii : null, attributes);
        }
    }
    
    /**
     * The {@link Geary.FolderPath} for the {@link mailbox}.
     *
     * This is constructed from the supplied {@link mailbox} and {@link delim} returned from the
     * server.  If the mailbox is the same as the supplied inbox_specifier, a canonical name for
     * the Inbox is returned.
     */
    public Geary.FolderPath get_path(MailboxSpecifier? inbox_specifier) {
        return mailbox.to_folder_path(delim, inbox_specifier);
    }
    
    public string to_string() {
        return "%s/%s".printf(mailbox.to_string(), attrs.to_string());
    }
}

