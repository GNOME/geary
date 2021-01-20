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
 * The properties of this class such as {@link name} and {@link
 * address} are stores decoded UTF-8, thus they must be re-encoded
 * using methods such as {@link to_rfc822_string} before being re-used
 * in a message envelope.
 *
 * See [[https://tools.ietf.org/html/rfc5322#section-3.4]]
 */
public class Geary.RFC822.MailboxAddress :
    Geary.MessageData.AbstractMessageData,
    Geary.MessageData.SearchableMessageData,
    Gee.Hashable<MailboxAddress>,
    DecodedMessageData {

    private static Regex? email_regex = null;

    private static unichar[] ATEXT = {
        '!', '#', '$', '%', '&', '\'', '*', '+', '-',
        '/', '=', '?', '^', '_', '`', '{', '|', '}', '~'
    };

    /** Determines if a string contains a valid RFC822 mailbox address. */
    public static bool is_valid_address(string address) {
        if (MailboxAddress.email_regex == null) {
            try {
                // http://www.regular-expressions.info/email.html
                // matches john@dep.aol.museum not john@aol...com
                MailboxAddress.email_regex = new Regex(
                    "[A-Z0-9._%+-]+@((?:[A-Z0-9-]+\\.)+[A-Z]{2}|localhost)",
                    RegexCompileFlags.CASELESS
                );
            } catch (RegexError e) {
                warning("Regex error validating email address: %s", e.message);
                return false;
            }
        }
        return MailboxAddress.email_regex.match(address);
    }

    private static string decode_name(string name) {
        return GMime.utils_header_decode_phrase(
            Geary.RFC822.get_parser_options(),
            prepare_header_text_part(name)
        );
    }

    private static string decode_address_part(string mailbox) {
        return GMime.utils_header_decode_text(
          Geary.RFC822.get_parser_options(),
          prepare_header_text_part(mailbox)
        );
    }

    private static bool display_name_needs_quoting(string name) {
        // Currently we only care if the name contains a comma, since
        // that will screw up the composer's address entry fields. See
        // issue #282. This might be able to be removed when the
        // composer doesn't parse recipients as a text list of
        // addresses.
        return (name.index_of(",") != -1);
    }

    private static bool local_part_needs_quoting(string local_part) {
        bool needs_quote = false;
        bool is_dot = false;
        if (!String.is_empty(local_part)) {
            int index = 0;
            for (;;) {
                unichar ch;
                if (!local_part.get_next_char(ref index, out ch)) {
                    break;
                }

                is_dot = (ch == '.');

                if (!(
                        // RFC 5322 ASCII
                        (ch >= 0x61 && ch <= 0x7A) || // a-z
                        (ch >= 0x41 && ch <= 0x5A) || // A-Z
                        (ch >= 0x30 && ch <= 0x39) || // 0-9
                        // RFC 6532 UTF8
                        (ch >= 0x80 && ch <= 0x07FF) ||      // UTF-8 2 byte
                        (ch >= 0x800 && ch <= 0xFFFF) ||     // UTF-8 3 byte
                        (ch >= 0x10000 && ch <= 0x10FFFF) || // UTF-8 4 byte
                        // RFC 5322 atext
                        (ch in ATEXT) ||
                        // RFC 5322 dot-atom (no leading quotes)
                        (is_dot && index > 1))) {
                    needs_quote = true;
                    break;
                }
            }
        }
        return needs_quote || is_dot; // no trailing dots
    }

    private static string quote_string(string needs_quoting) {
        StringBuilder builder = new StringBuilder();
        if (!String.is_empty(needs_quoting)) {
            builder.append_c('"');
            int index = 0;
            for (;;) {
                char ch = needs_quoting[index++];
                if (ch == String.EOS)
                    break;

                if (ch == '"' || ch == '\\') {
                    builder.append_c('\\');
                }

                builder.append_c(ch);
            }
            builder.append_c('"');
        }
        return builder.str;
    }

    private static string prepare_header_text_part(string part) {
        // Borrowed liberally from GMime's internal
        // _internet_address_decode_name() function.

        // see if a broken mailer has sent raw 8-bit information
        string text = (
            !GMime.utils_text_is_8bit(part.data)
            ? part
            : GMime.utils_decode_8bit(get_parser_options(), part.data)
        );

        text = GMime.utils_header_unfold(text);
        GMime.utils_unquote_string(text);

        // Sometimes quoted printables contain unencoded spaces which
        // trips up GMime, so we want to encode them all here.
        int offset = 0;
        int start;
        while ((start = text.index_of("=?", offset)) != -1) {
            // Find the closing marker.
            int end = text.index_of("?=", start + 2) + 2;
            if (end <= 1) {
                end = text.length;
            }

            // Replace any spaces inside the encoded string.
            string encoded = text.substring(start, end - start);
            if (encoded.contains("\x20")) {
                text = text.replace(encoded, encoded.replace("\x20", "_"));
            }
            offset = end;
        }

        return text;
    }


    /**
     * The optional human-readable part of the mailbox address.
     *
     * For "Dirk Gently <dirk@example.com>", this would be "Dirk Gently".
     *
     * The returned value has been unquoted and decoded into UTF-8.
     */
    public string? name { get; private set; }

    /**
     * The routing of the message (optional, obsolete).
     *
     * The returned value has been decoded into UTF-8.
     */
    public string? source_route { get; private set; }

    /**
     * The mailbox (local-part) portion of the mailbox's address.
     *
     * For "Dirk Gently <dirk@example.com>", this would be "dirk".
     *
     * The returned value has been decoded into UTF-8.
     */
    public string mailbox { get; private set; }

    /**
     * The domain portion of the mailbox's address.
     *
     * For "Dirk Gently <dirk@example.com>", this would be "example.com".
     *
     * The returned value has been decoded into UTF-8.
     */
    public string domain { get; private set; }

    /**
     * The complete address part of the mailbox address.
     *
     * For "Dirk Gently <dirk@example.com>", this would be "dirk@example.com".
     *
     * The returned value has been decoded into UTF-8.
     */
    public string address { get; private set; }


    /**
     * Constructs a new mailbox address from unquoted, decoded parts.
     *
     * The given name (if any) and address parts will be used
     * verbatim, and quoted or encoded if needed when serialising to
     * an RFC 822 mailbox address string.
     */
    public MailboxAddress(string? name, string address) {
        this.name = name;
        this.source_route = null;
        this.address = address;

        int atsign = Ascii.last_index_of(address, '@');
        if (atsign > 0) {
            this.mailbox = address[0:atsign];
            this.domain = address[atsign + 1:address.length];
        } else {
            this.mailbox = "";
            this.domain = "";
        }
    }

    public MailboxAddress.imap(string? name, string? source_route, string mailbox, string domain) {
        this.name = (name != null) ? decode_name(name) : null;
        this.source_route = source_route;
        this.mailbox = decode_address_part(mailbox);
        this.domain = domain;

        bool empty_mailbox = String.is_empty_or_whitespace(mailbox);
        bool empty_domain = String.is_empty_or_whitespace(domain);
        if (!empty_mailbox && !empty_domain) {
            this.address = "%s@%s".printf(mailbox, domain);
        } else if (empty_mailbox) {
            this.address = domain;
        } else if (empty_domain) {
            this.address = mailbox;
        } else {
            this.address = "";
        }
    }

    public MailboxAddress.from_rfc822_string(string rfc822) throws Error {
        GMime.InternetAddressList addrlist = GMime.InternetAddressList.parse(
            Geary.RFC822.get_parser_options(),
            rfc822
        );
        if (addrlist == null) {
            throw new Error.INVALID("Not a RFC822 mailbox address: %s", rfc822);
        }
        if (addrlist.length() != 1) {
            throw new Error.INVALID(
                "Not a single RFC822 mailbox address: %s", rfc822
            );
        }

        GMime.InternetAddress? addr = addrlist.get_address(0);
        // TODO: Handle group lists
        var mbox_addr = addr as GMime.InternetAddressMailbox;
        if (mbox_addr == null) {
            throw new Error.INVALID(
                "Group lists not currently supported: %s", rfc822
            );
        }

        this.from_gmime(mbox_addr);
    }

    public MailboxAddress.from_gmime(GMime.InternetAddressMailbox mailbox) {
        // GMime strips source route for us, so the address part
        // should only ever contain a single '@'
        string? name = mailbox.get_name();
        this.name = (
            !String.is_empty_or_whitespace(name)
            ? decode_name(name)
            : null
        );

        string address = mailbox.get_addr();
        int atsign = Ascii.last_index_of(address, '@');
        if (atsign == -1) {
            // No @ detected, try decoding in case a mailer (wrongly)
            // encoded the whole thing and re-try
            address = decode_address_part(address);
            atsign = Ascii.last_index_of(address, '@');
        }

        if (atsign >= 0) {
            this.mailbox = decode_address_part(address[0:atsign]);
            this.domain = address[atsign + 1:address.length];
            this.address = "%s@%s".printf(this.mailbox, this.domain);
        } else {
            this.mailbox = "";
            this.domain = "";
            this.address = decode_address_part(address);
        }
    }

    /**
     * Returns a full human-readable version of the mailbox address.
     *
     * This returns a formatted version of the address including
     * {@link name} (if present, not a spoof, and distinct from the
     * address) and {@link address} parts, suitable for display to
     * people. The string will have white space reduced and
     * non-printable characters removed, and the address will be
     * surrounded by angle brackets if a name is present, and if the
     * name contains a reserved character, it will be quoted.
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
        if (display_name_needs_quoting(clean_name)) {
            clean_name = quote_string(clean_name);
        }
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
        // look like an email address (unless it's the same as the
        // address part).
        if (!Geary.String.is_empty(this.name)) {
            if (Regex.match_simple(CONTROLS, this.name)) {
                is_spoof = true;
            } else if (has_distinct_name()) {
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
     * @return //true// if {@link name} is not empty, and the
     * normalised {@link address} part is not equal to the name part
     * when performing a case-insensitive comparison.
     */
    public bool has_distinct_name() {
        string name = Geary.String.reduce_whitespace(this.name);
        if (!Geary.String.is_empty(name)) {
            // Some software uses single quotes instead of double
            // quotes for name parts, which GMime ignores. Don't take
            // those into account if present. See GNOME/geary#491.
            if (name.length >= 2 &&
                name[0] == '\'' &&
                name[name.length - 1] == '\'') {
                name = name.substring(1, name.length - 2);
            }
        }

        bool ret = false;
        if (!Geary.String.is_empty(name)) {
            name = name.normalize().casefold();
            string address = Geary.String.reduce_whitespace(
                this.address.normalize().casefold()
            );
            ret = (name != address);
        }
        return ret;
    }

    /**
     * Returns the complete mailbox address, armoured for RFC 822 use.
     *
     * This method is similar to {@link to_full_display}, but only
     * checks for a distinct address (per Postel's Law) and not for
     * any spoofing, and does not strip extra white space or
     * non-printing characters.
     *
     * @return the RFC822 encoded form of the full address.
     */
    public string to_rfc822_string() {
        return has_distinct_name()
            ? "%s <%s>".printf(
                GMime.utils_header_encode_phrase(
                    Geary.RFC822.get_format_options(),
                    this.name,
                    null
                ),
                to_rfc822_address()
            )
            : to_rfc822_address();
    }

    /**
     * Returns the address part only, armoured for RFC 822 use.
     *
     * @return the RFC822 encoded form of the address, without angle
     * brackets.
     */
    public string to_rfc822_address() {
        // GMime.utils_header_encode_text won't quote if spaces or
        // quotes present, GMime.utils_quote_string will erroneously
        // quote if a '.'  is present (which at least Yahoo doesn't
        // like in SMTP return paths), and
        // GMime.utils_header_encode_text will use MIME encoding,
        // which is disallowed in mailboxes by RFC 2074 §5. So quote
        // manually.
        var address = "";
        if (this.mailbox != "") {
            address = this.mailbox;
            if (local_part_needs_quoting(address)) {
                address = quote_string(address);
            }
        }
        if (this.domain != "") {
            address = "%s@%s".printf(
                address,
                // XXX Need to punycode international domains.
                this.domain
            );
        }
        if (address == "") {
            // Both mailbox and domain are empty, i.e. there was no
            // '@' symbol in the address, so just assume the address
            // is a mailbox since this is not uncommon practice on
            // UNIX systems where mail is sent from a local account,
            // and it supports a greater range of characters than the
            // domain component
            address = this.address;
            if (local_part_needs_quoting(address)) {
                address = quote_string(address);
            }
        }
        return address;
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
     * Determines if this mailbox is equal to another by address.
     *
     * Equality is defined as case-insensitive comparison of the
     * {@link address} of both mailboxes.
     */
    public bool equal_to(MailboxAddress other) {
        return this == other || String.stri_equal(address, other.address);
    }

    /**
     * Determines if this mailbox is equal to another by address.
     *
     * This is suitable for determining equality for weaker cases such
     * as user searches. Here equality is defined as case-insensitive
     * comparison of the normalised, case-folded {@link address} and
     * the same for the given string.
     */
    public bool equal_normalized(string address) {
        return (
            this.address.normalize().casefold() == address.normalize().casefold()
        );
    }

    /**
     * Returns the RFC822 formatted version of the address.
     *
     * @see to_rfc822_string
     */
    public override string to_string() {
        return to_rfc822_string();
    }

}
