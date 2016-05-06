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
    SPAM,
    TRASH,
    OUTBOX,
    ARCHIVE;
    
    public unowned string get_display_name() {
        switch (this) {
            case INBOX:
                return _("Inbox");
            
            case DRAFTS:
                return _("Drafts");
            
            case SENT:
                return _("Sent Mail");
            
            case FLAGGED:
                return _("Starred");
            
            case IMPORTANT:
                return _("Important");
            
            case ALL_MAIL:
                return _("All Mail");
            
            case SPAM:
                return _("Spam");
            
            case TRASH:
                return _("Trash");
            
            case OUTBOX:
                return _("Outbox");
            
            case SEARCH:
                return _("Search");
            
            case ARCHIVE:
                return _("Archive");
            
            case NONE:
            default:
                return _("None");
        }
    }
    
    public bool is_outgoing() {
        return this == SENT || this == OUTBOX;
    }
}

