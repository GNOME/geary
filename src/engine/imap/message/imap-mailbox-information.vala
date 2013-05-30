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

public class Geary.Imap.MailboxInformation : Object {
    /**
     * The decoded mailbox name.
     *
     * See {@link MailboxParameter} for the encoded version of this string.
     */
    public string name { get; private set; }
    
    /**
     * The (optional) delimiter specified by the server.
     */
    public string? delim { get; private set; }
    
    /**
     * Folder attributes returned by the server.
     */
    public MailboxAttributes attrs { get; private set; }
    
    public MailboxInformation(string name, string? delim, MailboxAttributes attrs) {
        this.name = name;
        this.delim = delim;
        this.attrs = attrs;
    }
    
    /**
     * Will always return a list with at least one element in it.  If no delimiter is specified,
     * the name is returned as a single element.
     */
    public Gee.List<string> get_path() {
        Gee.List<string> path = new Gee.ArrayList<string>();
        
        if (!String.is_empty(delim)) {
            string[] split = name.split(delim);
            foreach (string str in split) {
                if (!String.is_empty(str))
                    path.add(str);
            }
        }
        
        if (path.size == 0)
            path.add(name);
        
        return path;
    }
    
    /**
     * The mailbox's name without parent folders.
     *
     * If name is non-empty, will return a non-empty value which is the final folder name (i.e.
     * the parent components are stripped).  If no delimiter is specified, the name is returned.
     */
    public string get_basename() {
        if (String.is_empty(delim))
            return name;
        
        int index = name.last_index_of(delim);
        if (index < 0)
            return name;
        
        string basename = name.substring(index + 1);
        
        return !String.is_empty(basename) ? basename : name;
    }
    
    /**
     * Decodes {@link ServerData} into a MailboxInformation representation.
     *
     * The ServerData must be the response to a LIST or XLIST command.
     *
     * @see ListCommand
     * @see ServerData.get_list
     */
    public static MailboxInformation decode(ServerData server_data) throws ImapError {
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
            
            attrlist.add(new MailboxAttribute(stringp.value));
        }
        
        // decode everything
        MailboxAttributes attributes = new MailboxAttributes(attrlist);
        StringParameter? delim = server_data.get_as_nullable_string(3);
        MailboxParameter mailbox = new MailboxParameter.from_string_parameter(
            server_data.get_as_string(4));
        
        // Set \Inbox to standard path
        if (Geary.Imap.MailboxAttribute.SPECIAL_FOLDER_INBOX in attributes) {
            return new MailboxInformation(Geary.Imap.Account.INBOX_NAME,
                (delim != null) ? delim.nullable_value : null, attributes);
        } else {
            return new MailboxInformation(mailbox.decode(),
                (delim != null) ? delim.nullable_value : null, attributes);
        }
    }
}

