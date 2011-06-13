/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Imap.MailboxInformation {
    public string name { get; private set; }
    public string delim { get; private set; }
    public MailboxAttributes attrs { get; private set; }
    
    public MailboxInformation(string name, string delim, MailboxAttributes attrs) {
        this.name = name;
        this.delim = delim;
        this.attrs = attrs;
    }
}

public class Geary.Imap.ListResults : Geary.Imap.CommandResults {
    private Gee.List<MailboxInformation> list;
    private Gee.Map<string, MailboxInformation> map;
    
    public ListResults(StatusResponse status_response, Gee.Map<string, MailboxInformation> map,
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
                StringParameter delim = data.get_as_string(3);
                StringParameter mailbox = data.get_as_string(4);
                
                if (!cmd.equals_ci(ListCommand.NAME) && !cmd.equals_ci(XListCommand.NAME)) {
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
                
                MailboxInformation info = new MailboxInformation(mailbox.value, delim.value,
                    new MailboxAttributes(attrlist));
                
                map.set(mailbox.value, info);
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

