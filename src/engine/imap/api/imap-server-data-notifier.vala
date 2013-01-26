/* Copyright 2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class Geary.Imap.ServerDataNotifier : Object {
    //
    // ServerData (always untagged)
    //
    
    public virtual signal void capability(Capabilities capabilities) {
    }
    
    public virtual signal void exists(int count) {
    }
    
    public virtual signal void expunge(MessageNumber msg_num) {
    }
    
    public virtual signal void fetch(FetchedData fetched_data) {
    }
    
    public virtual signal void flags(MailboxAttributes mailbox_attrs) {
    }
    
    public virtual signal void list(MailboxInformation mailbox_info) {
    }
    
    // TODO: LSUB results
    
    public virtual signal void recent(int count) {
    }
    
    // TODO: SEARCH results
    
    // TODO: STATUS results
    
    public ServerDataNotifier() {
    }
    
    public bool notify(ServerData server_data) throws ImapError {
        switch (server_data.server_data_type) {
            case ServerDataType.CAPABILITY:
                capability(CapabilityDecoder.decode(server_data));
            break;
            
            case ServerDataType.EXISTS:
                exists(ExistsDecoder.decode(server_data));
            break;
            
            case ServerDataType.EXPUNGE:
                expunge(ExpungedDecoder.decode(server_data));
            break;
            
            case ServerDataType.FETCH:
                fetch(FetchDecoder.decode(server_data));
            break;
            
            case ServerDataType.FLAGS:
                flags(FlagsDecoder.decode(server_data));
            break;
            
            case ServerDataType.LIST:
                list(ListDecoder.decode(server_data));
            break;
            
            case ServerDataType.RECENT:
                recent(RecentDecoder.decode(server_data));
            break;
            
            // TODO: LSUB, SEARCH, and STATUS
            case ServerDataType.STATUS:
            case ServerDataType.LSUB:
            case ServerDataType.SEARCH:
            default:
                return false;
        }
        
        return true;
    }
}

