/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * An abstract class describing a process for going through an SASL authentication transaction.
 *
 * Authenticators expect to use complete {@link Credentials}, i.e. user and pass must not be null.
 */

public abstract class Geary.Smtp.Authenticator : BaseObject {
    /**
     * The user-visible name for this {@link Authenticator}.
     */
    public string name { get; private set; }

    public Credentials credentials { get; private set; }

    protected Authenticator(string name, Credentials credentials) {
        this.name = name;
        this.credentials = credentials;

        if (!credentials.is_complete())
            message("Incomplete credentials supplied to SMTP authenticator %s", name);
    }

    /**
     * Returns a Request that is used to initiate the challenge-response.
     */
    public abstract Request initiate();

    /**
     * Returns a block of data that will be sent for that stage of the authentication challenge.
     * No line terminators should be present.  Various authentication schemes may also have their
     * own requirements.
     *
     * step is the zero-based step number of the challenge-response.  Response is the *last*
     * SMTP response from the server from the prior step (or from the initiate() request).
     *
     * Returns null if the Authenticator chooses to end the process in an orderly fashion.
     *
     * If an error is thrown, the entire process is aborted without any further I/O with the
     * server.  Generally this leaves the connection in a bad state and should be closed.
     */
    public abstract Memory.Buffer? challenge(int step, Response response) throws SmtpError;

    public virtual string to_string() {
        return name;
    }
}

