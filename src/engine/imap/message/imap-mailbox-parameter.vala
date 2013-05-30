/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A {@link StringParameter} that holds a mailbox reference (can be wildcarded).
 *
 * Used to juggle between our internal UTF-8 representation of mailboxes and IMAP's
 * odd "modified UTF-7" representation.  The value is stored in IMAP's encoded
 * format since that's how it comes across the wire.
 */

public class Geary.Imap.MailboxParameter : StringParameter {
    public MailboxParameter(string mailbox) {
        base (utf8_to_imap_utf7(mailbox));
    }
    
    public MailboxParameter.from_string_parameter(StringParameter string_parameter) {
        base (string_parameter.value);
    }
    
    private static string utf8_to_imap_utf7(string utf8) {
        try {
            return Geary.ImapUtf7.utf8_to_imap_utf7(utf8);
        } catch (ConvertError e) {
            debug("Error encoding mailbox name '%s': %s", utf8, e.message);
            return utf8;
        }
    }
    
    private static string imap_utf7_to_utf8(string imap_utf7) {
        try {
            return Geary.ImapUtf7.imap_utf7_to_utf8(imap_utf7);
        } catch (ConvertError e) {
            debug("Invalid mailbox name '%s': %s", imap_utf7, e.message);
            return imap_utf7;
        }
    }
    
    public string decode() {
        return imap_utf7_to_utf8(value);
    }
}

