/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public abstract class Geary.Imap.ServerResponse : RootParameters {
    public Tag tag { get; private set; }
    
    protected ServerResponse.reconstitute(RootParameters root) throws ImapError {
        base.clone(root);
        
        tag = new Tag.from_parameter(get_as_string(0));
    }
    
    public static ServerResponse from_server(RootParameters root) throws ImapError {
        if (ContinuationResponse.is_continuation_response(root))
            return new ContinuationResponse.reconstitute(root);
        
        // All CompletionStatusResponses are StatusResponses, so check for it first
        if (CompletionStatusResponse.is_completion_status_response(root))
            return new CompletionStatusResponse.reconstitute(root);
        
        // All CodedStatusResponses are StatusResponses, so check for it first
        if (CodedStatusResponse.is_coded_status_response(root))
            return new CodedStatusResponse.reconstitute(root);
        
        if (StatusResponse.is_status_response(root))
            return new StatusResponse.reconstitute(root);
        
        if (ServerData.is_server_data(root))
            return new ServerData.reconstitute(root);
        
        throw new ImapError.PARSE_ERROR("Unknown server response: %s", root.to_string());
    }
}

