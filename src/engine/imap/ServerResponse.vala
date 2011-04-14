/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public abstract class Geary.Imap.ServerResponse : RootParameters {
    public Tag tag { get; private set; }
    
    public ServerResponse(Tag tag) {
        this.tag = tag;
    }
    
    public ServerResponse.reconstitute(RootParameters root) throws ImapError {
        base.clone(root);
        
        tag = new Tag.from_parameter((StringParameter) get_as(0, typeof(StringParameter)));
    }
    
    // Returns true if the RootParameters represents a StatusResponse, otherwise they should be
    // treated as ServerData.
    public static ServerResponse from_server(RootParameters root, out bool is_status_response)
        throws ImapError {
        // must be at least two parameters: a tag and a status or a value
        if (root.get_count() < 2) {
            throw new ImapError.TYPE_ERROR("Too few parameters (%d) for server response",
                root.get_count());
        }
        
        Tag tag = new Tag.from_parameter((StringParameter) root.get_as(0, typeof(StringParameter)));
        if (tag.is_tagged()) {
            // Attempt to decode second parameter for predefined status codes (piggyback on
            // Status.decode's exception if this is invalid)
            StringParameter? statusparam = root.get(1) as StringParameter;
            if (statusparam != null)
                Status.decode(statusparam.value);
            
            // tagged and has proper status, so it's a status response
            is_status_response = true;
            
            return new StatusResponse.reconstitute(root);
        }
        
        is_status_response = false;
        
        return new ServerData.reconstitute(root);
    }
}

