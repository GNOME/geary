/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Imap.MailboxInformation {
    public string name { get; private set; }
    public string? delim { get; private set; }
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
}

public class Geary.Imap.ListResults : Geary.Imap.CommandResults {
    private Gee.List<MailboxInformation> list;
    private Gee.Map<string, MailboxInformation> map;
    
    private ListResults(StatusResponse status_response, Gee.Map<string, MailboxInformation> map,
        Gee.List<MailboxInformation> list) {
        base (status_response);
        
        this.map = map;
        this.list = list;
    }
    
    public static ListResults decode(CommandResponse response) {
        assert(response.is_sealed());
        
        Gee.List<MailboxInformation> list = new Gee.ArrayList<MailboxInformation>();
        Gee.Map<string, MailboxInformation> map = new Gee.HashMap<string, MailboxInformation>();
        foreach (ServerData data in response.server_data) {
            try {
                StringParameter cmd = data.get_as_string(1);
                ListParameter attrs = data.get_as_list(2);
                StringParameter? delim = data.get_as_nullable_string(3);
                MailboxParameter mailbox = new MailboxParameter.from_string_parameter(data.get_as_string(4));
                
                if (!cmd.equals_ci(ListCommand.NAME) && !cmd.equals_ci(ListCommand.XLIST_NAME)) {
                    debug("Bad list response \"%s\": Not marked as list or xlist response",
                        data.to_string());
                    
                    continue;
                }
                
                Gee.Collection<MailboxAttribute> attrlist = new Gee.ArrayList<MailboxAttribute>();
                foreach (Parameter attr in attrs.get_all()) {
                    StringParameter? stringp = attr as StringParameter;
                    if (stringp == null) {
                        debug("Bad list attribute \"%s\": Attribute not a string value",
                            data.to_string());
                        
                        continue;
                    }
                    
                    attrlist.add(new MailboxAttribute(stringp.value));
                }
                
                // Set \Inbox to standard path
                MailboxInformation info;
                MailboxAttributes attributes = new MailboxAttributes(attrlist);
                if (Geary.Imap.MailboxAttribute.SPECIAL_FOLDER_INBOX in attributes) {
                    info = new MailboxInformation(Geary.Imap.Account.INBOX_NAME,
                        (delim != null) ? delim.nullable_value : null, attributes);
                } else {
                    info = new MailboxInformation(mailbox.decode(),
                        (delim != null) ? delim.nullable_value : null, attributes);
                }
                
                map.set(mailbox.decode(), info);
                list.add(info);
            } catch (ImapError ierr) {
                debug("Unable to decode \"%s\": %s", data.to_string(), ierr.message);
            }
        }
        
        return new ListResults(response.status_response, map, list);
    }
    
    public int get_count() {
        return list.size;
    }
    
    public Gee.Collection<string> get_names() {
        return map.keys;
    }
    
    public Gee.List<MailboxInformation> get_all() {
        return list;
    }
    
    public MailboxInformation? get_info(string name) {
        return map.get(name);
    }
}

