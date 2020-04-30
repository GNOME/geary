/*
 * Copyright © 2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * The base class for objects implementing a client plugin.
 *
 * To implement a new plugin, have it derive from this type and
 * implement any additional extension interfaces (such as {@link
 * NotificationExtension}) as required.
 */

/**
 * Errors when plugins request resources from their contexts.
 */
public errordomain Plugin.Error {

    /** Raised when access to a requested resource was denied. */
    PERMISSION_DENIED,

    /** Raised when a requested resource was not found. */
    NOT_FOUND,

    /** Raised when a requested operation could not be carried out. */
    NOT_SUPPORTED;

}
