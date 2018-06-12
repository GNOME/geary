/*
 * Copyright 2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Google's proprietary OAuth 2 authentication.
 *
 * See [[http://tools.ietf.org/html/rfc4616]]
 */

public class Geary.Smtp.OAuth2Authenticator : Geary.Smtp.Authenticator {


    private const string OAUTH2_RESP = "user=%s\001auth=Bearer %s\001\001";


    public OAuth2Authenticator(Credentials credentials) {
        base ("XOAUTH2", credentials);
    }

    public override Request initiate() {
        return new Request(Command.AUTH, { "xoauth2" });
    }

    public override Memory.Buffer? challenge(int step, Response response)
        throws SmtpError {
        Memory.Buffer? buf = null;
        switch (step) {
        case 0:
            // The initial AUTH command
            buf = new Memory.StringBuffer(
                Base64.encode(
                    OAUTH2_RESP.printf(
                        credentials.user ?? "",
                        credentials.token ?? ""
                    ).data
                )
            );
            break;

        case 1:
            // Server sent a challenge, which will be a Base64 encoded
            // JSON blob and which indicates a login failure. We don't
            // really care about that (do we?) though since once
            // we acknowledge it with a zero-length string the server
            // will respond with a SMTP error.
            buf = new Memory.StringBuffer("");
            break;
        }
        return buf;
    }
}
