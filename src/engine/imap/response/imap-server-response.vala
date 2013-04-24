/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public abstract class Geary.Imap.ServerResponse : RootParameters {
    public Tag tag { get; private set; }
    
    public ServerResponse(Tag tag) {
        this.tag = tag;
    }
    
    public ServerResponse.migrate(RootParameters root) throws ImapError {
        base.migrate(root);
        
        tag = new Tag.from_parameter(get_as_string(0));
    }
    
    // The RootParameters are migrated and will be stripped upon exit.
    public static ServerResponse migrate_from_server(RootParameters root, out Type response_type)
        throws ImapError {
        Tag tag = new Tag.from_parameter(root.get_as_string(0));
        if (tag.is_tagged()) {
            // Attempt to decode second parameter for predefined status codes (piggyback on
            // Status.decode's exception if this is invalid)
            StringParameter? statusparam = root.get_if_string(1);
            if (statusparam != null)
                Status.decode(statusparam.value);
            
            // tagged and has proper status, so it's a status response
            response_type = Type.STATUS_RESPONSE;
            
            return new StatusResponse.migrate(root);
        } else if (tag.is_continuation()) {
            // nothing to decode; everything after the tag is human-readable stuff
            response_type = Type.CONTINUATION_RESPONSE;
            
            return new ContinuationResponse.migrate(root);
        }
        
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

