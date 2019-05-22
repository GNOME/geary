/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * SASL's PLAIN authentication schema implemented as an {@link Authenticator}.
 *
 * See [[http://tools.ietf.org/html/rfc4616]]
 */

public class Geary.Smtp.PlainAuthenticator : Geary.Smtp.Authenticator {
    private static uint8[] nul = { '\0' };

    public PlainAuthenticator(Credentials credentials) {
        base ("PLAIN", credentials);
    }

    public override Request initiate() {
        return new Request(Command.AUTH, { "PLAIN" });
    }

    public override Memory.Buffer? challenge(int step, Response response) throws SmtpError {
        // only a single challenge is issued in PLAIN
        if (step > 0)
            return null;

        Memory.GrowableBuffer growable = new Memory.GrowableBuffer();
        // skip the "authorize" field, which we don't support
        growable.append(nul);
        growable.append(credentials.user.data);
        growable.append(nul);
        growable.append((credentials.token ?? "").data);

        // convert to Base64
        return new Memory.StringBuffer(Base64.encode(growable.get_bytes().get_data()));
    }
}

