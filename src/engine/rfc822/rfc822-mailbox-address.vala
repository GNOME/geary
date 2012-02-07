/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.RFC822.MailboxAddress {
    public string? name { get; private set; }
    public string? source_route { get; private set; }
    public string mailbox { get; private set; }
    public string domain { get; private set; }
    public string address { get; private set; }
    
    public MailboxAddress(string? name, string address) {
        this.name = name;
        this.address = address;
        
        source_route = null;
        
        int atsign = address.index_of_char('@');
        if (atsign > 0) {
            mailbox = address.slice(0, atsign);
            domain = address.slice(atsign + 1, address.length);
        }
    }
    
    public MailboxAddress.imap(string? name, string? source_route, string mailbox, string domain) {
        this.name = (name != null) ? decode_name(name) : null;
        this.source_route = source_route;
        this.mailbox = mailbox;
        this.domain = domain;
        
        address = "%s@%s".printf(mailbox, domain);
    }
    
    // Borrowed liberally from GMime's internal _internet_address_decode_name() function.
    private static string decode_name(string name) {
        // see if a broken mailer has sent raw 8-bit information
        string phrase = name.validate() ? name : GMime.utils_decode_8bit(name, name.length);
        
        // unquote the string and decode the phrase
        GMime.utils_unquote_string(phrase);
        
        return GMime.utils_header_decode_phrase(phrase);
    }
    
    /**
     * Returns a human-readable formatted address, showing the name (if available) and the email 
     * address in angled brackets.
     */
    public string get_full_address() {
        return String.is_empty(name) ? address : "%s <%s>".printf(name, address);
    }
    
    /**
     * Returns a simple address, that is, no human-readable name and the email address in angled
     * brackets.
     */
    public string get_simple_address() {
        return "<%s>".printf(address);
    }
    
    /**
     * Returns a human-readable pretty address, showing only the name, but if unavailable, the
     * mailbox name (that is, the account name without the domain).
     */
    public string get_short_address() {
        return name ?? mailbox;
    }
    
    public string to_rfc822_string() {
        return String.is_empty(name)
            ? "<%s>".printf(address)
            : "%s <%s>".printf(GMime.utils_quote_string(name), address);
    }
    
    public string to_string() {
        return get_full_address();
    }
}

