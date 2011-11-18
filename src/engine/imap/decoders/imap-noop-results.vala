/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Imap.NoopResults : Geary.Imap.CommandResults {
    public Gee.List<MessageNumber>? expunged { get; private set; }
    /**
     * -1 if "exists" result not returned by server.
     */
    public int exists { get; private set; }
    public MailboxAttributes? flags { get; private set; }
    /**
     * -1 if "recent" result not returned by server.
     */
    public int recent { get; private set; }
    
    public NoopResults(StatusResponse status_response, Gee.List<MessageNumber>? expunged, int exists,
        MailboxAttributes? flags, int recent) {
        base (status_response);
        
        this.expunged = expunged;
        this.exists = exists;
        this.flags = flags;
        this.recent = recent;
    }
    
    public static NoopResults decode(CommandResponse response) {
        assert(response.is_sealed());
        
        Gee.List<MessageNumber> expunged = new Gee.ArrayList<MessageNumber>();
        MailboxAttributes? flags = null;
        int exists = -1;
        int recent = -1;
        
        foreach (ServerData data in response.server_data) {
            UnsolicitedServerData? unsolicited = UnsolicitedServerData.from_server_data(data);
            if (unsolicited == null) {
                message("NOOP server data \"%s\" unrecognized", data.to_string());
                
                continue;
            }
            
            if (unsolicited.exists >= 0)
                exists = unsolicited.exists;
            
            if (unsolicited.recent >= 0)
                recent = unsolicited.recent;
            
            if (unsolicited.flags != null)
                flags = unsolicited.flags;
            
            if (unsolicited.expunge != null)
                expunged.add(unsolicited.expunge);
        }
        
        return new NoopResults(response.status_response, (expunged.size > 0) ? expunged : null,
            exists, (flags != null && flags.size > 0) ? flags : null, recent);
    }
    
    public bool has_exists() {
        return exists >= 0;
    }
    
    public bool has_recent() {
        return recent >= 0;
    }
}

