/* Copyright 2011-2013 Yorba Foundation
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
    public UID? uid_next { get; private set; }
    public UIDValidity? uid_validity { get; private set; }
    /**
     * -1 if not set.
     */
    public int unseen { get; private set; }
    
    private StatusResults(StatusResponse status_response, string mailbox, int messages, int recent,
        UID? uid_next, UIDValidity? uid_validity, int unseen) {
        base (status_response);
        
        this.mailbox = mailbox;
        this.messages = messages;
        this.recent = recent;
        this.uid_next = uid_next;
        this.uid_validity = uid_validity;
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
        MailboxParameter mailbox = new MailboxParameter.from_string_parameter(data.get_as_string(2));
        ListParameter values = data.get_as_list(3);
        
        if (!cmd.equals_ci(StatusCommand.NAME)) {
            throw new ImapError.PARSE_ERROR("Bad STATUS command name in response \"%s\"",
                response.to_string());
        }
        
        int messages = -1;
        int recent = -1;
        UID? uid_next = null;
        UIDValidity? uid_validity = null;
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
                        uid_next = new UID(valuep.as_int());
                    break;
                    
                    case StatusDataType.UIDVALIDITY:
                        uid_validity = new UIDValidity(valuep.as_int());
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
        
        return new StatusResults(response.status_response, mailbox.decode(), messages, recent, uid_next,
            uid_validity, unseen);
    }
}

