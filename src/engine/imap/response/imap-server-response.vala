/* Copyright 2016 Software Freedom Conservancy Inc.
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
    public Quirks quirks { get; private set; }


    protected ServerResponse(Tag tag, Quirks quirks) {
        this.tag = tag;
        this.quirks = quirks;
    }

    /**
     * Converts the {@link RootParameters} into a ServerResponse.
     *
     * The supplied root is "stripped" of its children.
     */
    protected ServerResponse.migrate(RootParameters root,
                                     Quirks quirks)
        throws ImapError {
        base.migrate(root);
        this.quirks = quirks;

        if (!has_tag()) {
            throw new ImapError.INVALID("Server response does not have a tag token: %s", to_string());
        }
        this.tag = get_tag();
    }

}
