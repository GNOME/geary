/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * An immutable representation of an RFC 822 mailbox address.
 *
 * See [[https://tools.ietf.org/html/rfc5322#section-3.4]]
 */
public class Geary.RFC822.MailboxAddress : Geary.MessageData.SearchableMessageData,
    Gee.Hashable<MailboxAddress>, BaseObject {

    /** Determines if a string contains a valid RFC822 mailbox address. */
    public static bool is_valid_address(string address) {
        try {
            // http://www.regular-expressions.info/email.html
            // matches john@dep.aol.museum not john@aol...com
            Regex email_regex =
                new Regex("[A-Z0-9._%+-]+@((?:[A-Z0-9-]+\\.)+[A-Z]{2}|localhost)",
                    RegexCompileFlags.CASELESS);
            return email_regex.match(address);
        } catch (RegexError e) {
            debug("Regex error validating email address: %s", e.message);
            return false;
        }
    }


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

        int atsign = address.last_index_of_char('@');
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

        this.address = "%s@%s".printf(mailbox, domain);
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
     * Returns a full human-readable version of the mailbox address.
     *
     * This returns a formatted version of the address including
     * {@link name} (if present, not a spoof, and distinct from the
     * address) and {@link address} parts, suitable for display to
     * people. The string will have white space reduced and
     * non-printable characters removed, and the address will be
     * surrounded by angle brackets if a name is present.
     *
     * If you need a form suitable for sending a message, see {@link
     * to_rfc822_string} instead.
     *
     * @see has_distinct_name
     * @see is_spoofed
     * @param open optional string to use as the opening bracket for
     * the address part, defaults to //<//
     * @param close optional string to use as the closing bracket for
     * the address part, defaults to //>//
     * @return the cleaned //name// part if present, not spoofed and
     * distinct from //address//, followed by a space then the cleaned
     * //address// part, cleaned and enclosed within the specified
     * brackets.
     */
    public string to_full_display(string open = "<", string close = ">") {
        string clean_name = Geary.String.reduce_whitespace(this.name);
        string clean_address = Geary.String.reduce_whitespace(this.address);
        return (!has_distinct_name() || is_spoofed())
            ? clean_address
            : "%s %s%s%s".printf(clean_name, open, clean_address, close);
    }

    /**
     * Returns a short human-readable version of the mailbox address.
     *
     * This returns a shortened version of the address suitable for
     * display to people: Either the {@link name} (if present and not
     * a spoof) or the {@link address} part otherwise. The string will
     * have white space reduced and non-printable characters removed.
     *
     * @see is_spoofed
     * @return the cleaned //name// part if present and not spoofed,
     * or else the cleaned //address// part, cleaned but without
     * brackets.
     */
    public string to_short_display() {
        string clean_name = Geary.String.reduce_whitespace(this.name);
        string clean_address = Geary.String.reduce_whitespace(this.address);
        return String.is_empty(clean_name) || is_spoofed()
            ? clean_address
            : clean_name;
    }

    /**
     * Returns a human-readable version of the address part.
     *
     * @param open optional string to use as the opening bracket,
     * defaults to //<//
     * @param close optional string to use as the closing bracket,
     * defaults to //>//
     * @return the {@link address} part, cleaned and enclosed within the
     * specified brackets.
     */
    public string to_address_display(string open = "<", string close = ">") {
        return open + Geary.String.reduce_whitespace(this.address) + close;
    }

    /**
     * Returns true if the email syntax is valid.
     */
    public bool is_valid() {
        return is_valid_address(address);
    }

    /**
     * Determines if the mailbox address appears to have been spoofed.
     *
     * Using recipient and sender mailbox addresses where the name
     * part is also actually a valid RFC822 address
     * (e.g. "you@example.com <jerk@spammer.com>") is a common tactic
     * used by spammers and malware authors to exploit MUAs that will
     * display the name part only if present. It also enables more
     * sophisticated attacks such as
     * [[https://www.mailsploit.com/|Mailsploit]], which uses
     * Quoted-Printable or Base64 encoded nulls, new lines, @'s and
     * other characters to further trick MUAs into displaying a bogus
     * address.
     *
     * This method attempts to detect such attacks by examining the
     * {@link name} for non-printing characters and determining if it
     * is by itself also a valid RFC822 address.
     *
     * @return //true// if the complete decoded address contains any
     * non-printing characters, if the name part is also a valid
     * RFC822 address, or if the address part is not a valid RFC822
     * address.
     */
    public bool is_spoofed() {
        // Empty test and regexes must apply to the raw values, not
        // clean ones, otherwise any control chars present will have
        // been lost
        const string CONTROLS = "[[:cntrl:]]+";

        bool is_spoof = false;

        // 1. Check the name part contains no controls and doesn't
        // look like an email address
        if (!Geary.String.is_empty(this.name)) {
            if (Regex.match_simple(CONTROLS, this.name)) {
                is_spoof = true;
            } else {
                // Clean up the name as usual, but remove all
                // whitespace so an attack can't get away with a name
                // like "potus @ whitehouse . gov"
                string clean_name = Geary.String.reduce_whitespace(this.name);
                clean_name = clean_name.replace(" ", "");
                if (is_valid_address(clean_name)) {
                    is_spoof = true;
                }
            }
        }

        // 2. Check the mailbox part of the address doesn't contain an
        // @. Is actually legal if quoted, but rarely (never?) found
        // in the wild and better be safe than sorry.
        if (!is_spoof && this.mailbox.contains("@")) {
            is_spoof = true;
        }

        // 3. Check the address doesn't contain any spaces or
        // controls. Again, space in the mailbox is allowed if quoted,
        // but in practice should rarely be used.
        if (!is_spoof && Regex.match_simple(Geary.String.WS_OR_NP, this.address)) {
            is_spoof = true;
        }

        return is_spoof;
    }

    /**
     * Determines if the name part is different to the address part.
     *
     * @return //true// if {@link name} is not empty, and the cleaned
     * versions of the name part and {@link address} are not equal.
     */
    public bool has_distinct_name() {
        string clean_name = Geary.String.reduce_whitespace(this.name);
        return (
            !Geary.String.is_empty(clean_name) &&
            clean_name != Geary.String.reduce_whitespace(this.address)
        );
    }

    /**
     * Returns the address suitable for insertion into an RFC822 message.
     *
     * @return the RFC822 quoted form of the full address.
     */
    public string to_rfc822_string() {
        return has_distinct_name()
            ? "%s <%s>".printf(GMime.utils_quote_string(this.name), this.address)
            : this.address;
    }

    /**
     * See Geary.MessageData.SearchableMessageData.
     */
    public string to_searchable_string() {
        return has_distinct_name()
            ? "%s <%s>".printf(this.name, this.address)
            : this.address;
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

    /**
     * Returns the RFC822 formatted version of the address.
     *
     * @see to_rfc822_string
     */
    public string to_string() {
        return to_rfc822_string();
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

