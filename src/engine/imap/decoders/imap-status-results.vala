/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Imap.StatusResults : Geary.Imap.CommandResults {
    public string mailbox { get; private set; }
    /**
     * -1 if not set.
     */
    public int messages { get; private set; }
    /**
     * -1 if not set.
     */
    public int recent { get; private set; }
    public UID? uidnext { get; private set; }
    public UIDValidity? uidvalidity { get; private set; }
    /**
     * -1 if not set.
     */
    public int unseen { get; private set; }
    
    public StatusResults(StatusResponse status_response, string mailbox, int messages, int recent,
        UID? uidnext, UIDValidity? uidvalidity, int unseen) {
        base (status_response);
        
        this.mailbox = mailbox;
        this.messages = messages;
        this.recent = recent;
        this.uidnext = uidnext;
        this.uidvalidity = uidvalidity;
        this.unseen = unseen;
    }
    
    public static StatusResults decode(CommandResponse response) throws ImapError {
        assert(response.is_sealed());
        
        // only use the first untagged response of status; zero is a problem, more than one are
        // ignored
        if (response.server_data.size == 0)
            throw new ImapError.PARSE_ERROR("No STATUS response line: \"%s\"", response.to_string());
        
        ServerData data = response.server_data[0];
        StringParameter cmd = data.get_as_string(1);
        StringParameter mailbox = data.get_as_string(2);
        ListParameter values = data.get_as_list(3);
        
        if (!cmd.equals_ci(StatusCommand.NAME)) {
            throw new ImapError.PARSE_ERROR("Bad STATUS command name in response \"%s\"",
                response.to_string());
        }
        
        int messages = -1;
        int recent = -1;
        UID? uidnext = null;
        UIDValidity? uidvalidity = null;
        int unseen = -1;
        
        for (int ctr = 0; ctr < values.get_count(); ctr += 2) {
            try {
                StringParameter typep = values.get_as_string(ctr);
                StringParameter valuep = values.get_as_string(ctr + 1);
                
                switch (StatusDataType.from_parameter(typep)) {
                    case StatusDataType.MESSAGES:
                        messages = valuep.as_int(-1, int.MAX);
                    break;
                    
                    case StatusDataType.RECENT:
                        recent = valuep.as_int(-1, int.MAX);
                    break;
                    
                    case StatusDataType.UIDNEXT:
                        uidnext = new UID(valuep.as_int());
                    break;
                    
                    case StatusDataType.UIDVALIDITY:
                        uidvalidity = new UIDValidity(valuep.as_int());
                    break;
                    
                    case StatusDataType.UNSEEN:
                        unseen = valuep.as_int(-1, int.MAX);
                    break;
                    
                    default:
                        message("Bad STATUS data type %s", typep.value);
                    break;
                }
            } catch (ImapError ierr) {
                message("Bad value at %d/%d in STATUS response \"%s\": %s", ctr, ctr + 1,
                    response.to_string(), ierr.message);
            }
        }
        
        return new StatusResults(response.status_response, mailbox.value, messages, recent, uidnext, 
            uidvalidity, unseen);
    }
}

