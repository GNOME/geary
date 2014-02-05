/* Copyright 2011-2014 Yorba Foundation
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
     * Indicates a request failed according to a returned response.
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
}

