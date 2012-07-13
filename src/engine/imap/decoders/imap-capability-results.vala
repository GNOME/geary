/* Copyright 2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Imap.CapabilityResults : Geary.Imap.CommandResults {
    public Capabilities capabilities { get; private set; }
    
    private CapabilityResults(StatusResponse status_response, Capabilities capabilities) {
        base (status_response);
        
        this.capabilities = capabilities;
    }
    
    public static bool is_capability_response(CommandResponse response) {
        if (response.server_data.size < 1)
            return false;
        
        StringParameter? cmd = response.server_data[0].get_if_string(1);
        
        return (cmd != null && cmd.equals_ci(CapabilityCommand.NAME));
    }
    
    public static CapabilityResults decode(CommandResponse response) throws ImapError {
        assert(response.is_sealed());
        
        if (!is_capability_response(response))
            throw new ImapError.PARSE_ERROR("Unrecognized CAPABILITY response line: \"%s\"", response.to_string());
        
        ServerData data = response.server_data[0];
        
        // parse the remaining parameters in the response as capabilities
        Capabilities capabilities = new Capabilities();
        for (int ctr = 2; ctr < data.get_count(); ctr++) {
            StringParameter? param = data.get_if_string(ctr);
            if (param != null)
                capabilities.add_parameter(param);
        }
        
        return new CapabilityResults(response.status_response, capabilities);
    }
}

