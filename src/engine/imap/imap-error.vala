/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Possible Errors thrown by various components in the {@link Geary.Imap} namespace.
 *
 */

public errordomain Geary.ImapError {
    /**
     * Indicates a basic parsing error, syntactic in nature.
     */
    PARSE_ERROR,
    /**
     * Indicates a type conversion error.
     *
     * This largely occurs inside of {@link Imap.ListParameter}, where various
     * {@link Imap.Parameter}s are retrieved by specific type according to the flavor of the
     * response.
     */
    TYPE_ERROR,
    /**
     * Indicates an operation failed because a network connection had not been established.
     */
    NOT_CONNECTED,
    /**
     * Indicates the connection is already established or authentication has been granted.
     */
    ALREADY_CONNECTED,

    /**
     * A request failed due to an explicit or implicit BAD response.
     *
     * An explicit BAD response is as per RFC 3501 §7.3.1. An implicit
     * BAD response is when the server returns an unexpected response,
     * for example, sends a status response for the same command twice.
     *
     * See [[https://tools.ietf.org/html/rfc3501#section-7.1.3]].
     */
    SERVER_ERROR,

    /**
     * Indicates that an operation could not proceed without prior authentication.
     */
    UNAUTHENTICATED,
    /**
     * An operation is not supported by the IMAP stack or by the server.
     */
    NOT_SUPPORTED,
    /**
     * Indicates a basic parsing error, semantic in nature.
     */
    INVALID,
    /**
     * A network connection of some kind failed due to an expired timer.
     *
     * This indicates a local time out, not one reported by the server.
     */
    TIMED_OUT,

    /**
     * The remote IMAP server not currently available.
     *
     * This does not indicate a network error, rather it indicates a
     * connection to the server was established but the server
     * indicated it is not currently servicing the connection.
     */
    UNAVAILABLE;

}
