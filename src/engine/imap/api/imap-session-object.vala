/*
 * Copyright 2018 Michael Gratton <mike@vee.net>.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Base class for IMAP client session objects.
 *
 * Since a client session can come and go as the server and network
 * changes, IMAP client objects need to be sensitive to the state of
 * the connection. This abstract class manages access to an IMAP
 * client session for objects that use connections to an IMAP server,
 * ensuring it is no longer available if the client session is
 * disconnected.
 *
 * This class is ''not'' thread safe.
 */
public abstract class Geary.Imap.SessionObject : BaseObject {


    /** Determines if this object has a valid session or not. */
    public bool is_valid { get { return this.session != null; } }

    private string id;
    private ClientSession? session;


    /** Fired if the object's connection to the server is lost. */
    public signal void disconnected(ClientSession.DisconnectReason reason);


    /**
     * Constructs a new IMAP object with the given session.
     */
    protected SessionObject(string id, ClientSession session) {
        this.id = id;
        this.session = session;
        this.session.disconnected.connect(on_disconnected);
    }

    ~SessionObject() {
        if (close() != null) {
            debug("%s: destroyed without releasing its session".printf(this.id));
        }
    }

    /**
     * Drops this object's association with its client session.
     *
     * Calling this method unhooks the object from its session, and
     * makes it unavailable for further use. This does //not//
     * disconnect the client session from its server.
     *
     * @return the old IMAP client session, for returning to the pool,
     * etc, if any.
     */
    public virtual ClientSession? close() {
        ClientSession? old_session = this.session;
        this.session = null;

        if (old_session != null) {
            old_session.disconnected.disconnect(on_disconnected);
        }

        return old_session;
    }

    /**
     * Returns a string representation of this object for debugging.
     */
    public virtual string to_string() {
        return "%s:%s".printf(
            this.id,
            this.session != null ? this.session.to_string() : "(session dropped)"
        );
    }

    /**
     * Obtains IMAP session the server for use by this object.
     *
     * @throws ImapError.NOT_CONNECTED if the session with the server
     * server has been dropped via {@link close}, or because
     * the connection was lost.
     */
    protected ClientSession claim_session()
        throws ImapError {
        if (this.session == null) {
            throw new ImapError.NOT_CONNECTED("IMAP object has no session");
        }
        return this.session;
    }

    private void on_disconnected(ClientSession.DisconnectReason reason) {
        debug("%s: DISCONNECTED %s", to_string(), reason.to_string());

        close();
        disconnected(reason);
    }

}
