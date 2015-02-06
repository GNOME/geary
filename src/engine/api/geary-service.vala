/* Copyright 2014-2015 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * The type of mail service provided by a particular destination.
 */
public enum Geary.Service {
    IMAP,
    SMTP;
    
    /**
     * Returns a user-visible label for the {@link Service}.
     */
    public string user_label() {
        switch (this) {
            case IMAP:
                return _("IMAP");
            
            case SMTP:
                return _("SMTP");
            
            default:
                assert_not_reached();
        }
    }
}

/**
 * A bitfield of {@link Service}s.
 */
[Flags]
public enum Geary.ServiceFlag {
    IMAP,
    SMTP;
    
    public bool has_imap() {
        return (this & IMAP) == IMAP;
    }
    
    public bool has_smtp() {
        return (this & SMTP) == SMTP;
    }
}

