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
    public Gee.List<FetchResults>? flags { get; private set; }
    /**
     * -1 if "recent" result not returned by server.
     */
    public int recent { get; private set; }
    
    public NoopResults(StatusResponse status_response, Gee.List<MessageNumber>? expunged, int exists,
        Gee.List<FetchResults>? flags, int recent) {
        base (status_response);
        
        this.expunged = expunged;
        this.exists = exists;
        this.flags = flags;
        this.recent = recent;
    }
    
    public static NoopResults decode(CommandResponse response) {
        assert(response.is_sealed());
        
        Gee.List<MessageNumber> expunged = new Gee.ArrayList<MessageNumber>();
        Gee.List<FetchResults> flags = new Gee.ArrayList<FetchResults>();
        int exists = -1;
        int recent = -1;
        
        foreach (ServerData data in response.server_data) {
            try {
                int ordinal = data.get_as_string(1).as_int().clamp(-1, int.MAX);
                ServerDataType type = ServerDataType.from_parameter(data.get_as_string(2));
                
                switch (type) {
                    case ServerDataType.EXPUNGE:
                        expunged.add(new MessageNumber(ordinal));
                    break;
                    
                    case ServerDataType.EXISTS:
                        exists = ordinal;
                    break;
                    
                    case ServerDataType.RECENT:
                        recent = ordinal;
                    break;
                    
                    case ServerDataType.FETCH:
                        flags.add(FetchResults.decode_data(response.status_response, data));
                    break;
                    
                    default:
                        message("NOOP server data type \"%s\" unrecognized", type.to_string());
                    break;
                }
            } catch (ImapError ierr) {
                message("NOOP decode error for \"%s\": %s", data.to_string(), ierr.message);
            }
        }
        
        return new NoopResults(response.status_response, (expunged.size > 0) ? expunged : null,
            exists, (flags.size > 0) ? flags : null, recent);
    }
    
    public bool has_exists() {
        return exists >= 0;
    }
    
    public bool has_recent() {
        return recent >= 0;
    }
}

