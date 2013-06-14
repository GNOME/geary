/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A response sent from the server to client.
 *
 * ServerResponses can take various shapes, including tagged/untagged and some common forms where
 * status and status text are supplied.
 *
 * See [[http://tools.ietf.org/html/rfc3501#section-7]] for more information.
 */

public abstract class Geary.Imap.ServerResponse : RootParameters {
    public Tag tag { get; private set; }
    
    protected ServerResponse(Tag tag) {
        this.tag = tag;
    }
    
    /**
     * Converts the {@link RootParameters} into a ServerResponse.
     *
     * The supplied root is "stripped" of its children.
     */
    public ServerResponse.migrate(RootParameters root) throws ImapError {
        base.migrate(root);
        
        if (!has_tag())
            throw new ImapError.INVALID("Server response does not have a tag token: %s", to_string());
        
        tag = get_tag();
    }
    
    /**
     * Migrate the contents of RootParameters into a new, properly-typed ServerResponse.
     *
     * The returned ServerResponse may be a {@link ContinuationResponse}, {@link ServerData},
     * or a generic {@link StatusResponse}.
     *
     * The RootParameters will be migrated and stripped clean upon exit.
     *
     * @throws ImapError.PARSE_ERROR if not a known form of ServerResponse.
     */
    public static ServerResponse migrate_from_server(RootParameters root) throws ImapError {
        if (ContinuationResponse.is_continuation_response(root))
            return new ContinuationResponse.migrate(root);
        
        if (StatusResponse.is_status_response(root))
            return new StatusResponse.migrate(root);
        
        if (ServerData.is_server_data(root))
            return new ServerData.migrate(root);
        
        throw new ImapError.PARSE_ERROR("Unknown server response: %s", root.to_string());
    }
}

