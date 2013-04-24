/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public enum Geary.SpecialFolderType {
    NONE,
    INBOX,
    DRAFTS,
    SENT,
    FLAGGED,
    IMPORTANT,
    ALL_MAIL,
    SPAM,
    TRASH,
    OUTBOX;
    
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
            
            case NONE:
            default:
                return _("None");
        }
    }
    
    public bool is_outgoing() {
        return this == SENT || this == OUTBOX;
    }
}

