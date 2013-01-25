/* Copyright 2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class Geary.Imap.ServerResponseNotifier : Object {
    //
    // Untagged StatusResponses
    //
    
    public virtual signal void untagged_bad(ResponseCode? response_code, string? message) {
    }
    
    public virtual signal void untagged_bye(ResponseCode? response_code, string? message) {
    }
    
    public virtual signal void untagged_ok(ResponseCode? response_code, string? message) {
    }
    
    public virtual signal void untagged_no(ResponseCode? response_code, string? message) {
    }
    
    public virtual signal void untagged_preauth(ResponseCode? response_code, string? message) {
    }
    
    //
    // Tagged CompletionStatusReponses (IMAP only allows BAD, OK, and NO)
    //
    
    public virtual signal void completed_bad(ResponseCode? response_code, string? message) {
    }
    
    public virtual signal void completed_ok(ResponseCode? response_code, string? message) {
    }
    
    public virtual signal void completed_no(ResponseCode? response_code, string? message) {
    }
    
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
    
    public ServerResponseNotifier() {
    }
    
    public bool notify(ServerResponse server_resp) throws ImapError {
        if (server_resp.tag.is_tagged()) {
            debug("ServerResponseNotifier should not be used to notify of tagged responses: %s",
                server_resp.to_string());
            
            return false;
        }
        
        CompletionStatusResponse completion_resp as CompletionStatusResponse;
        if (completion_resp != null)
            return notify_completion_response(completion_resp);
        
        StatusResponse? status_resp = resp as StatusResponse;
        if (status_resp != null)
            return notify_status_response(status_resp);
        
        ServerData server_data = resp as ServerData;
        if (server_data != null)
            return notify_server_data(server_data);
        
        debug("Unable to decode server response of type %s", resp.get_type().name());
        
        return false;
    }
    
    private bool notify_completion_response(CompletionStatusResponse completion_resp) throws ImapError {
        switch (completion_resp.status) {
            case Status.BAD:
                completion_bad(completion_resp.response_code, completion_resp.text);
            break;
            
            case Status.NO:
                completion_no(completion_resp.response_code, completion_resp.text);
            break;
            
            case Status.OK:
                completion_ok(completion_resp.response_code, completion_resp.text);
            break;
            
            default:
                return false;
        }
        
        return true;
    }
    
    private bool notify_status_response(StatusResponse status_resp) throws ImapError {
        switch (status_resp.status) {
            case Status.BAD:
                untagged_bad(status_resp.response_code, status_resp.text);
            break;
            
            case Status.BYE:
                untagged_bad(status_resp.response_code, status_resp.text);
            break;
            
            case Status.NO:
                untagged_bad(status_resp.response_code, status_resp.text);
            break;
            
            case Status.OK:
                untagged_bad(status_resp.response_code, status_resp.text);
            break;
            
            case Status.PREAUTH:
                untagged_bad(status_resp.response_code, status_resp.text);
            break;
            
            default:
                return false;
        }
        
        return true;
    }
    
    private bool notify_server_data(ServerData server_data) throws ImapError {
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

