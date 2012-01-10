/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Imap.SelectExamineResults : Geary.Imap.CommandResults {
    /**
     * -1 if not specified.
     */
    public int exists { get; private set; }
    /**
     * -1 if not specified.
     */
    public int recent { get; private set; }
    /**
     * -1 if not specified.
     */
    public int unseen { get; private set; }
    public UIDValidity? uid_validity { get; private set; }
    public UID? uid_next { get; private set; }
    public Flags? flags { get; private set; }
    public Flags? permanentflags { get; private set; }
    public bool readonly { get; private set; }
    
    private SelectExamineResults(StatusResponse status_response, int exists, int recent, int unseen,
        UIDValidity? uid_validity, UID? uid_next, Flags? flags, Flags? permanentflags, bool readonly) {
        base (status_response);
        
        this.exists = exists;
        this.recent = recent;
        this.unseen = unseen;
        this.uid_validity = uid_validity;
        this.uid_next = uid_next;
        this.flags = flags;
        this.permanentflags = permanentflags;
        this.readonly = readonly;
    }
    
    public static SelectExamineResults decode(CommandResponse response) throws ImapError {
        assert(response.is_sealed());
        
        int exists = -1;
        int recent = -1;
        int unseen = -1;
        UIDValidity? uid_validity = null;
        UID? uid_next = null;
        MessageFlags? flags = null;
        MessageFlags? permanentflags = null;
        
        bool readonly = true;
        try {
            readonly = response.status_response.response_code.get_as_string(0).value.down() != "read-write";
        } catch (ImapError ierr) {
            message("Invalid SELECT/EXAMINE read-write indicator: %s",
                response.status_response.to_string());
        }
        
        foreach (ServerData data in response.server_data) {
            try {
                StringParameter stringp = data.get_as_string(1);
                switch (stringp.value.down()) {
                    case "ok":
                        // ok lines are structured like StatusResponses
                        StatusResponse ok_response = new StatusResponse.reconstitute(data);
                        if (ok_response.response_code == null) {
                            message("Invalid SELECT/EXAMINE response \"%s\": no response code",
                                data.to_string());
                            
                            break;
                        }
                        
                        // the ResponseCode is what we're interested in
                        switch (ok_response.response_code.get_code_type()) {
                            case ResponseCodeType.UNSEEN:
                                unseen = ok_response.response_code.get_as_string(1).as_int(0, int.MAX);
                            break;
                            
                            case ResponseCodeType.UIDVALIDITY:
                                uid_validity = new UIDValidity(
                                    ok_response.response_code.get_as_string(1).as_int());
                            break;
                            
                            case ResponseCodeType.UIDNEXT:
                                uid_next = new UID(ok_response.response_code.get_as_string(1).as_int());
                            break;
                            
                            case ResponseCodeType.PERMANENT_FLAGS:
                                permanentflags = MessageFlags.from_list(
                                    ok_response.response_code.get_as_list(1));
                            break;
                            
                            default:
                                message("Unknown line in SELECT/EXAMINE response: \"%s\"", data.to_string());
                            break;
                        }
                    break;
                    
                    case "flags":
                        flags = MessageFlags.from_list(data.get_as_list(2));
                    break;
                    
                    default:
                        // if second parameter is a type descriptor, stringp is an ordinal
                        switch (ServerDataType.from_parameter(data.get_as_string(2))) {
                            case ServerDataType.EXISTS:
                                exists = stringp.as_int(0, int.MAX);
                            break;
                            
                            case ServerDataType.RECENT:
                                recent = stringp.as_int(0, int.MAX);
                            break;
                            
                            default:
                                message("Unknown line in SELECT/EXAMINE response: \"%s\"", data.to_string());
                            break;
                        }
                    break;
                }
            } catch (ImapError ierr) {
                message("SELECT/EXAMINE decode error for \"%s\": %s", data.to_string(), ierr.message);
            }
        }
        
        // flags, exists, and recent are required
        if (flags == null || exists < 0 || recent < 0)
            throw new ImapError.PARSE_ERROR("Incomplete SELECT/EXAMINE Response: \"%s\"", response.to_string());
        
        return new SelectExamineResults(response.status_response, exists, recent, unseen,
            uid_validity, uid_next, flags, permanentflags, readonly);
    }
}

