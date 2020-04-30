/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public enum Geary.SpecialFolderType {

    NONE,
    INBOX,
    SEARCH,
    DRAFTS,
    SENT,
    FLAGGED,
    IMPORTANT,
    ALL_MAIL,
    JUNK,
    TRASH,
    OUTBOX,
    ARCHIVE;

    public bool is_outgoing() {
        return this == SENT || this == OUTBOX;
    }

}
