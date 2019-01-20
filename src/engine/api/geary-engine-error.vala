/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public errordomain Geary.EngineError {

    /** An account, folder or other object has not been opened. */
    OPEN_REQUIRED,

    /** An account, folder or other object has already been opened. */
    ALREADY_OPEN,

    /** An object with the same name or id already exists. */
    ALREADY_EXISTS,

    /** An account, folder or other object has already been closed. */
    ALREADY_CLOSED,

    /** An account, folder or other object must be closed first. */
    CLOSE_REQUIRED,

    /** An object with the given name or id does not exist. */
    NOT_FOUND,

    /** The parameters for a function or method call are somehow invalid. */
    BAD_PARAMETERS,

    /** An email did not contain all required fields. */
    INCOMPLETE_MESSAGE,

    /** A remote resource is no longer available. */
    SERVER_UNAVAILABLE,

    /** The account database or other local resource is corrupted. */
    CORRUPT,

    /** The account database or other local resource cannot be accessed. */
    PERMISSIONS,

    /** The account database or other local resource has a bad version. */
    VERSION,

    /** A remote resource does not support a given operation. */
    UNSUPPORTED
}
