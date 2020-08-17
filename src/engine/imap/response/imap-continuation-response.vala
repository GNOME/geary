/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A server response indicating that the server is ready to accept more data for the current
 * command.
 *
 * The only requirement for a ContinuationResponse is that its {@link Tag} must be a
 * {@link Tag.CONTINUATION_VALUE} ("+").  All other information in the response is optional.
 *
 * See [[http://tools.ietf.org/html/rfc3501#section-7.5]] for more information.
 */

public class Geary.Imap.ContinuationResponse : ServerResponse {


    private ContinuationResponse(Quirks quirks) {
        base(Tag.get_continuation(), quirks);
    }

    /**
     * Converts the {@link RootParameters} into a {@link ContinuationResponse}.
     *
     * The supplied root is "stripped" of its children.  This may happen even if an exception is
     * thrown.  It's recommended to use {@link is_continuation_response} prior to this call.
     */
    public ContinuationResponse.migrate(RootParameters root, Quirks quirks)
        throws ImapError {
        base.migrate(root, quirks);
        if (!tag.is_continuation())
            throw new ImapError.INVALID("Tag %s is not a continuation", tag.to_string());
    }

    /**
     * Returns true if the {@link RootParameters}'s {@link Tag} is a continuation character ("+").
     */
    public static bool is_continuation_response(RootParameters root) {
        Tag? tag = root.get_tag();
        return tag != null ? tag.is_continuation() : false;
    }
}
