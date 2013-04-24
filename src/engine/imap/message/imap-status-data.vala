/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class Geary.Imap.StatusData : Object {
    // NOTE: This must be negative one; other values won't work well due to how the values are
    // decoded
    public const int UNSET = -1;
    
    public string mailbox { get; private set; }
    /**
     * UNSET if not set.
     */
    public int messages { get; private set; }
    /**
     * UNSET if not set.
     */
    public int recent { get; private set; }
    public UID? uid_next { get; private set; }
    public UIDValidity? uid_validity { get; private set; }
    /**
     * UNSET if not set.
     */
    public int unseen { get; private set; }
    
    public StatusData(string mailbox, int messages, int recent, UID? uid_next,
        UIDValidity? uid_validity, int unseen) {
        this.mailbox = mailbox;
        this.messages = messages;
        this.recent = recent;
        this.uid_next = uid_next;
        this.uid_validity = uid_validity;
        this.unseen = unseen;
    }
    
    public static StatusData decode(ServerData server_data) throws ImapError {
        if (!server_data.get_as_string(1).equals_ci(StatusCommand.NAME)) {
            throw new ImapError.PARSE_ERROR("Bad STATUS command name in response \"%s\"",
                response.to_string());
        }
        
        int messages = UNSET;
        int recent = UNSET;
        UID? uid_next = null;
        UIDValidity? uid_validity = null;
        int unseen = UNSET;
        
        ListParameter values = server_data.get_as_list(3);
        for (int ctr = 0; ctr < values.get_count(); ctr += 2) {
            try {
                StringParameter typep = values.get_as_string(ctr);
                StringParameter valuep = values.get_as_string(ctr + 1);
                
                switch (StatusDataType.from_parameter(typep)) {
                    case StatusDataType.MESSAGES:
                        // see note at UNSET
                        messages = valuep.as_int(-1, int.MAX);
                    break;
                    
                    case StatusDataType.RECENT:
                        // see note at UNSET
                        recent = valuep.as_int(-1, int.MAX);
                    break;
                    
                    case StatusDataType.UIDNEXT:
                        uid_next = new UID(valuep.as_int());
                    break;
                    
                    case StatusDataType.UIDVALIDITY:
                        uid_validity = new UIDValidity(valuep.as_int());
                    break;
                    
                    case StatusDataType.UNSEEN:
                        // see note at UNSET
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
        
        return new StatusData(server_data.get_as_string(2).value, messages, recent, uid_next,
            uid_validity, unseen);
    }
}

