/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public errordomain Geary.NonblockingError {
    /**
     * Indicates a call was made when it shouldn't have been; that the primitive was in such a
     * state that it cannot properly respond or account for the requested change.
     */
    INVALID
}

