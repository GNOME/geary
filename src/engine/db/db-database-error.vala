/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public errordomain Geary.DatabaseError {
    GENERAL,
    OPEN_REQUIRED,
    BUSY,
    CORRUPT,
    ACCESS,
    MEMORY,
    ABORT,
    INTERRUPT,
    LIMITS,
    TYPESPEC,
    FINISHED,
    SCHEMA_VERSION
}

