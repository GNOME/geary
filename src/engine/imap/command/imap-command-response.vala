/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Imap.CommandResponse : Object {
    public Gee.List<ServerData> server_data { get; private set; }
    public StatusResponse? status_response { get; private set; }
    
    public CommandResponse() {
        server_data = new Gee.ArrayList<ServerData>();
    }
    
    public void add_server_data(ServerData data) {
        assert(!is_sealed());
        
        server_data.add(data);
    }
    
    public void seal(StatusResponse status_response) {
        assert(!is_sealed());
        
        this.status_response = status_response;
    }
    
    public bool is_sealed() {
        return (status_response != null);
    }
    
    public string to_string() {
        StringBuilder builder = new StringBuilder();
        
        foreach (ServerData data in server_data)
            builder.append("%s\n".printf(data.to_string()));
        
        if (status_response != null)
            builder.append(status_response.to_string());
        
        if (!is_sealed())
            builder.append("(incomplete command response)");
        
        return builder.str;
    }
}

