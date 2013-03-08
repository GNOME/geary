/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

/**
 * Some ServerData returned by the server may be unsolicited and not an expected part of the command.
 * "Unsolicited" is contextual, since these fields may be returned as a natural part of a command
 * (SELECT/EXAMINE or EXPUNGE) or expected (NOOP).  In other situations, they must be dealt with
 * out-of-band and the unsolicited ServerData not considered as part of the normal CommandResponse.
 *
 * Note that only one of the fields (exists, recent, expunge, or flags) will be valid for any
 * ServerData; it's impossible that more than one will be valid.
 */
public class Geary.Imap.UnsolicitedServerData : BaseObject {
    /**
     * -1 means not found in ServerData
     */
    public int exists { get; private set; }
    /**
     * -1 means not found in ServerData
     */
    public int recent { get; private set; }
    /**
     * null means not found in ServerData
     */
    public MessageNumber? expunge { get; private set; }
    /**
     * null means not found in ServerData
     */
    public MailboxAttributes? flags { get; private set; }
    
    private UnsolicitedServerData(int exists, int recent, MessageNumber? expunge, MailboxAttributes? flags) {
        this.exists = exists;
        this.recent = recent;
        this.expunge = expunge;
        this.flags = flags;
    }
    
    /**
     * Returns null if not recognized as unsolicited server data.
     */
    public static UnsolicitedServerData? from_server_data(ServerData data) {
        // Note that unsolicited server data is formatted the same save for FLAGS:
        //
        // * 47 EXISTS
        // * 3 EXPUNGE
        // * FLAGS (\answered \flagged \deleted \seen)
        // * 15 RECENT
        //
        // Also note that these server data are *not* unsolicited if they're associated with their
        // "natural" command (i.e. SELECT/EXAMINE, NOOP) although the NOOP decoder uses this object
        // to do its decoding.
        //
        // Also note that the unsolicited data is EXPUNGE while the EXPUNGE command expects
        // EXPUNGED (past tense) server data to be returned
        
        // first unsolicited param is always a string
        StringParameter? first_string = data.get_if_string(1);
        if (first_string == null)
            return null;
        
        // second might be a string or a list
        StringParameter? second_string = data.get_if_string(2);
        ListParameter? second_list = data.get_if_list(2);
        if (second_string == null && second_list == null)
            return null;
        
        // determine command and value by types
        StringParameter? cmdparam = null;
        StringParameter? strparam = null;
        ListParameter? listparam = null;
        if (second_list != null) {
            cmdparam = first_string;
            listparam = second_list;
        } else {
            cmdparam = second_string;
            strparam = first_string;
        }
        
        try {
            switch (cmdparam.value.down()) {
                case "exists":
                    return (strparam != null)
                        ? new UnsolicitedServerData(strparam.as_int(), -1, null, null)
                        : null;
                
                case "recent":
                    return (strparam != null)
                        ? new UnsolicitedServerData(-1, strparam.as_int(), null, null)
                        : null;
                
                case "expunge":
                case "expunged": // Automatically handles ExpungeCommand results
                    return (strparam != null)
                        ? new UnsolicitedServerData(-1, -1, new MessageNumber(strparam.as_int()), null)
                        : null;
                
                case "flags":
                    return (listparam != null)
                        ? new UnsolicitedServerData(-1, -1, null, MailboxAttributes.from_list(listparam))
                        : null;
                
                default:
                    // an unrecognized parameter
                    return null;
            }
        } catch (ImapError err) {
            debug("Unable to decode unsolicited data \"%s\": %s", data.to_string(), err.message);
            
            return null;
        }
    }
    
    public string to_string() {
        if (exists >= 0)
            return "EXISTS %d".printf(exists);
        
        if (recent >= 0)
            return "RECENT %d".printf(recent);
        
        if (expunge != null)
            return "EXPUNGE %s".printf(expunge.to_string());
        
        if (flags != null)
            return "FLAGS %s".printf(flags.to_string());
        
        return "(invalid unsolicited data)";
    }
}


