/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * SASL's LOGIN authentication schema implemented as an {@link Authenticator}.
 *
 * LOGIN is obsolete but still widely in use and provided for backward compatibility.
 *
 * See [[https://tools.ietf.org/html/draft-murchison-sasl-login-00]]
 */

public class Geary.Smtp.LoginAuthenticator : Geary.Smtp.Authenticator {
    public LoginAuthenticator(Credentials credentials) {
        base ("LOGIN", credentials);
    }

    public override Request initiate() {
        return new Request(Command.AUTH, { "login" });
    }

    public override Memory.Buffer? challenge(int step, Response response) throws SmtpError {
        switch (step) {
            case 0:
                return new Memory.StringBuffer(Base64.encode(credentials.user.data));

            case 1:
                return new Memory.StringBuffer(Base64.encode((credentials.token ?? "").data));

            default:
                return null;
        }
    }
}

