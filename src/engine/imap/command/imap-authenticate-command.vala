/*
 * Copyright 2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * An IMAP AUTHENTICATE command.
 *
 * See [[http://tools.ietf.org/html/rfc3501#section-6.2.2]]
 */
public class Geary.Imap.AuthenticateCommand : Command {


    public const string NAME = "authenticate";

    private const string OAUTH2_METHOD = "xoauth2";
    private const string OAUTH2_RESP = "user=%s\001auth=Bearer %s\001\001";


    public string method { get; private set; }


    private AuthenticateCommand(string method, string data) {
        base(NAME, { method, data });
        this.method = method;
    }

    public AuthenticateCommand.oauth2(string user, string token) {
        string encoded_token = Base64.encode(
            OAUTH2_RESP.printf(user, token).data
        );
        this(OAUTH2_METHOD, encoded_token);
    }

    public ContinuationParameter
        continuation_requested(ContinuationResponse response)
        throws ImapError {
        if (this.method != AuthenticateCommand.OAUTH2_METHOD) {
            throw new ImapError.INVALID("Unexpected continuation request");
        }

        // Continuation will be a Base64 encoded JSON blob and which
        // indicates a login failure. We don't really care about that
        // (do we?) though since once we acknowledge it with a
        // zero-length response the server will respond with an IMAP
        // error.
        return new ContinuationParameter(new uint8[0]);
    }

    public override string to_string() {
        return "%s %s %s <token>".printf(
            tag.to_string(), this.name, this.method
        );
    }

}
