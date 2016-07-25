/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * An immutable object containing a representation of an Internet email address.
 *
 * See [[https://tools.ietf.org/html/rfc2822#section-3.4]]
 */

public class Geary.RFC822.MailboxAddress : Geary.MessageData.SearchableMessageData,
    Gee.Hashable<MailboxAddress>, BaseObject {
    internal delegate string ListToStringDelegate(MailboxAddress address);
    
    /**
     * The optional user-friendly name associated with the {@link MailboxAddress}.
     *
     * For "Dirk Gently <dirk@example.com>", this would be "Dirk Gently".
     */
    public string? name { get; private set; }
    
    /**
     * The routing of the message (optional, obsolete).
     */
    public string? source_route { get; private set; }
    
    /**
     * The mailbox (local-part) portion of the {@link MailboxAddress}.
     *
     * For "Dirk Gently <dirk@example.com>", this would be "dirk".
     */
    public string mailbox { get; private set; }
    
    /**
     * The domain portion of the {@link MailboxAddress}.
     *
     * For "Dirk Gently <dirk@example.com>", this would be "example.com".
     */
    public string domain { get; private set; }
    
    /**
     * The address specification of the {@link MailboxAddress}.
     *
     * For "Dirk Gently <dirk@example.com>", this would be "dirk@example.com".
     */
    public string address { get; private set; }

    public MailboxAddress(string? name, string address) {
        this.name = name;
        this.address = address;

        source_route = null;

        int atsign = address.index_of_char('@');
        if (atsign > 0) {
            mailbox = address.slice(0, atsign);
            domain = address.slice(atsign + 1, address.length);
        } else {
            mailbox = "";
            domain = "";
        }
    }

    public MailboxAddress.imap(string? name, string? source_route, string mailbox, string domain) {
        this.name = (name != null) ? decode_name(name) : null;
        this.source_route = source_route;
        this.mailbox = mailbox;
        this.domain = domain;
        
        address = "%s@%s".printf(mailbox, domain);
    }

    public MailboxAddress.from_rfc822_string(string rfc822) throws RFC822Error {
        InternetAddressList addrlist = InternetAddressList.parse_string(rfc822);
        if (addrlist == null)
            return;

        int length = addrlist.length();
        for (int ctr = 0; ctr < length; ctr++) {
            InternetAddress? addr = addrlist.get_address(ctr);

            // TODO: Handle group lists
            InternetAddressMailbox? mbox_addr = addr as InternetAddressMailbox;
            if (mbox_addr != null) {
                this(mbox_addr.get_name(), mbox_addr.get_addr());
                return;
            }
        }
        throw new RFC822Error.INVALID("Could not parse RFC822 address: %s", rfc822);
    }

    // Borrowed liberally from GMime's internal _internet_address_decode_name() function.
    private static string decode_name(string name) {
        // see if a broken mailer has sent raw 8-bit information
        string text = name.validate() ? name : GMime.utils_decode_8bit(name, name.length);

        // unquote the string and decode the text
        GMime.utils_unquote_string(text);

        // Sometimes quoted printables contain unencoded spaces which trips up GMime, so we want to
        // encode them all here.
        int offset = 0;
        int start;
        while ((start = text.index_of("=?", offset)) != -1) {
            // Find the closing marker.
            int end = text.index_of("?=", start + 2) + 2;
            if (end == -1) {
                end = text.length;
            }

            // Replace any spaces inside the encoded string.
            string encoded = text.substring(start, end - start);
            if (encoded.contains("\x20")) {
                text = text.replace(encoded, encoded.replace("\x20", "_"));
            }
            offset = end;
        }

        return GMime.utils_header_decode_text(text);
    }

    /**
     * Returns a human-readable formatted address, showing the name (if available) and the email 
     * address in angled brackets.  No RFC822 quoting is performed.
     *
     * @see to_rfc822_string
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

    /**
     * Returns true if the email syntax is valid.
     */
    public bool is_valid() {
        return is_valid_address(address);
    }
    
    /**
     * Returns true if the email syntax is valid.
     */
    public static bool is_valid_address(string address) {
        try {
            // http://www.regular-expressions.info/email.html
            // matches john@dep.aol.museum not john@aol...com
            Regex email_regex =
                new Regex("[A-Z0-9._%+-]+@(?:[A-Z0-9-]+\\.)+[A-Z]{2,5}",
                    RegexCompileFlags.CASELESS);
            return email_regex.match(address);
        } catch (RegexError e) {
            debug("Regex error validating email address: %s", e.message);
            return false;
        }
    }
    
    /**
     * Returns the address suitable for insertion into an RFC822 message.  RFC822 quoting is
     * performed if required.
     *
     * @see get_full_address
     */
    public string to_rfc822_string() {
        return String.is_empty(name)
            ? address
            : "%s <%s>".printf(GMime.utils_quote_string(name), address);
    }
    
    /**
     * See Geary.MessageData.SearchableMessageData.
     */
    public string to_searchable_string() {
        return get_full_address();
    }
    
    public uint hash() {
        return String.stri_hash(address);
    }
    
    /**
     * Equality is defined as a case-insensitive comparison of the {@link address}.
     */
    public bool equal_to(MailboxAddress other) {
        return this != other ? String.stri_equal(address, other.address) : true;
    }

    public bool equal_normalized(string address) {
        return this.address.normalize().casefold() == address.normalize().casefold();
    }

    public string to_string() {
        return get_full_address();
    }
    
    internal static string list_to_string(Gee.List<MailboxAddress> addrs,
        string empty, ListToStringDelegate to_s) {
        switch (addrs.size) {
            case 0:
                return empty;
            
            case 1:
                return to_s(addrs[0]);
            
            default:
                StringBuilder builder = new StringBuilder();
                foreach (MailboxAddress addr in addrs) {
                    if (!String.is_empty(builder.str))
                        builder.append(", ");
                    
                    builder.append(to_s(addr));
                }
                
                return builder.str;
        }
    }
}

