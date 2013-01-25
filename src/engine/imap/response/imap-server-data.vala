/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Imap.ServerData : ServerResponse {
    public ServerDataType server_data_type { get; private set; }
    
    public ServerData.reconstitute(RootParameters root) throws ImapError {
        base.reconstitute(root);
        
        server_data_type = ServerDataType.from_response(this);
    }
    
    public static bool is_server_data(RootParameters root) {
        try {
            ServerDataType.from_response(root);
            
            return true;
        } catch (ImapError ierr) {
            return false;
        }
    }
    
    public Capabilities get_capabilities() throws ImapError {
        if (server_data_type != ServerDataType.CAPABILITY)
            throw new ImapError.PARSE_ERROR("Not CAPABILITY data: %s", to_string());
        
        Capabilities capabilities = new Capabilities();
        for (int ctr = 2; ctr < get_count(); ctr++) {
            StringParameter? param = get_if_string(ctr);
            if (param != null)
                capabilities.add_parameter(param);
        }
        
        return capabilities;
    }
    
    public int get_exists() throws ImapError {
        if (server_data_type != ServerDataType.EXISTS)
            throw new ImapError.PARSE_ERROR("Not EXISTS data: %s", to_string());
        
        return get_as_string(1).as_int(0);
    }
    
    public MessageNumber get_expunge() throws ImapError {
        if (server_data_type != ServerDataType.EXPUNGE)
            throw new ImapError.PARSE_ERROR("Not EXPUNGE data: %s", to_string());
        
        return new MessageNumber(get_as_string(1).as_int());
    }
    
    public FetchedData get_fetch() throws ImapError {
        if (server_data_type != ServerDataType.FETCH)
            throw new ImapError.PARSE_ERROR("Not FETCH data: %s", to_string());
        
        return FetchedData.decode(this);
    }
    
    public MailboxAttributes get_flags() throws ImapError {
        if (server_data_type != ServerDataType.FLAGS)
            throw new ImapError.PARSE_ERROR("Not FLAGS data: %s", to_string());
        
        return MailboxAttributes.from_list(get_as_list(2));
    }
    
    public MailboxInformation get_list() throws ImapError {
        if (server_data_type != ServerDataType.LIST)
            throw new ImapError.PARSE_ERROR("Not LIST data: %s", to_string());
        
        return MailboxInformation.decode(this);
    }
}

