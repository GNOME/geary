/* Copyright 2013-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * The root of all IMAP mailbox paths.
 *
 * Because IMAP has peculiar requirements about its mailbox paths (in particular, Inbox is
 * guaranteed at the root and is named case-insensitive, and that delimiters are particular to
 * each path), this class ensure certain requirements are held throughout the library.
 */

private class Geary.Imap.FolderRoot : Geary.FolderRoot {
    public bool is_inbox { get; private set; }
    
    public FolderRoot(string basename, string? default_separator) {
        bool init_is_inbox;
        string normalized_basename = init(basename, out init_is_inbox);
        
        base (normalized_basename, default_separator, !init_is_inbox, true);
        
        is_inbox = init_is_inbox;
    }
    
    // This is the magic that ensures the canonical IMAP Inbox name is used throughout the engine
    private static string init(string basename, out bool is_inbox) {
        if (MailboxSpecifier.is_inbox_name(basename)) {
            is_inbox = true;
            
            return MailboxSpecifier.CANONICAL_INBOX_NAME;
        }
        
        is_inbox = false;
        
        return basename;
    }
}

