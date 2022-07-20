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
public abstract class Geary.Imap.SessionObject : BaseObject, Logging.Source {


    /** Determines if this object has a valid session or not. */
    public bool is_valid { get { return this.session != null; } }

    /** {@inheritDoc} */
    public Logging.Source? logging_parent { get { return _logging_parent; } }
    private weak Logging.Source? _logging_parent = null;

    private ClientSession? session;


    /** Fired if the object's connection to the server is lost. */
    public signal void disconnected(ClientSession.DisconnectReason reason);


    /**
     * Constructs a new IMAP object with the given session.
     */
    protected SessionObject(ClientSession session) {
        this.session = session;
        this.session.notify["protocol-state"].connect(on_session_state_change);
    }

    ~SessionObject() {
        if (close() != null) {
            debug("Destroyed without releasing its session");
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
            old_session.notify["protocol-state"].disconnect(
                on_session_state_change
            );
        }

        return old_session;
    }

    /** {@inheritDoc} */
    public virtual Logging.State to_logging_state() {
        return new Logging.State(
            this,
            this.session != null ? this.session.to_string() : "no session"
        );
    }

    /** Sets the session's logging parent. */
    internal void set_logging_parent(Logging.Source parent) {
        this._logging_parent = parent;
    }

    /**
     * Returns a valid IMAP client session for use by this object.
     *
     * @throws ImapError.NOT_CONNECTED if the client session has been
     * dropped via {@link close}, if the client session is logging out
     * or has been closed, or because the connection to the server was
     * lost.
     */
    protected virtual ClientSession get_session()
        throws ImapError {
        if (this.session == null ||
            this.session.protocol_state == NOT_CONNECTED) {
            throw new ImapError.NOT_CONNECTED(
                "IMAP object has no session or is not connected"
            );
        }
        return this.session;
    }

    private void on_session_state_change() {
        if (this.session != null &&
            this.session.protocol_state == NOT_CONNECTED) {
            // Disconnect reason will null when the session is being
            // logged out but the logout command has not yet been
            // completed.
            var reason =
                this.session.disconnected ==
                    ClientSession.DisconnectReason.NULL ?
                ClientSession.DisconnectReason.LOCAL_CLOSE :
                this.session.disconnected;
            close();
            disconnected(reason);
        }
    }

}
