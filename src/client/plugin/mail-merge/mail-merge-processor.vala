/*
 * Copyright © 2020 Michael Gratton <mike@vee.net>.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * Substitutes merge fields in an email with actual data.
 */
public class MailMerge.Processor : GLib.Object {


    public const Geary.Email.Field REQUIRED_FIELDS = (
        ENVELOPE | Geary.Email.REQUIRED_FOR_MESSAGE
    );


    private const string FIELD_START = "{{";
    private const string FIELD_END = "}}";


    private struct Parser {

        public unowned string text;
        public int index;
        public bool spent;
        public bool at_field_start;
        public bool at_field_end;

        public Parser(string text) {
            this.text = text;
            this.index = 0;
            this.spent = (text.length == 0);
            this.at_field_start = text.has_prefix(FIELD_START);
            this.at_field_end = false;
        }

        public string read_text() {
            this.at_field_end = false;

            int start = this.index;
            char c = this.text[this.index];
            while (c != 0) {
                this.index++;
                if (c == FIELD_START[0] &&
                    this.text[this.index] == FIELD_START[1]) {
                    this.index--;
                    this.at_field_start = true;
                    break;
                }
                c = this.text[this.index];
            }
            if (c == 0) {
                this.spent = true;
            }
            return this.text.slice(start, this.index);
        }

        public string read_field() {
            this.at_field_start = false;

            // Skip the opening field separator
            this.index += FIELD_START.length;

            int start = this.index;
            char c = this.text[this.index];
            while (c != 0) {
                this.index++;
                if (c == FIELD_END[0]) {
                    if (this.text[this.index] == FIELD_END[1]) {
                        this.index++;
                        this.at_field_end = true;
                        break;
                    }
                }
                c = this.text[this.index];
            }
            var end = this.index;
            if (this.at_field_end) {
                // Don't include the closing field separator
                end -= FIELD_END.length;
            } else {
                // No closing field separator found, so not a valid
                // field. Move start back so it includes the opening
                // field separator
                start -= FIELD_START.length;
            }
            if (c == 0 || this.index == this.text.length) {
                this.spent = true;
            }
            return this.text.slice(start, end);
        }

    }


    public static string to_field(string name) {
        return FIELD_START + name + FIELD_END;
    }

    public static bool is_mail_merge_template(Geary.Email email)
        throws GLib.Error {
        var found = (
            (email.subject != null &&
             contains_field(email.subject.to_rfc822_string())) ||
            (email.to != null &&
             contains_field(email.to.to_rfc822_string())) ||
            (email.cc != null &&
             contains_field(email.cc.to_rfc822_string())) ||
            (email.bcc != null &&
             contains_field(email.bcc.to_rfc822_string())) ||
            (email.reply_to != null &&
             contains_field(email.bcc.to_rfc822_string())) ||
            (email.sender != null &&
             contains_field(email.sender.to_rfc822_string()))
        );
        if (!found) {
            var message = email.get_message();
            var body = (
                message.has_plain_body()
                ? message.get_plain_body(false, null)
                : message.get_html_body(null)
            );
            found = contains_field(body);
        }
        return found;
    }

    public static bool contains_field(string text) {
        var parser = Parser(text);
        var found = false;
        while (!parser.spent) {
            if (parser.at_field_start) {
                parser.read_field();
                if (parser.at_field_end) {
                    found = true;
                    break;
                }
            } else {
                parser.read_text();
            }
        }
        return found;
    }


    /** The email template being processed. */
    public Geary.Email template {
        get; private set;
    }

    /** The email constructed by the processor. */
    public Geary.ComposedEmail? email {
        get; private set; default = null;
    }

    /** A list of data fields missing when processing the template. */
    public Gee.List<string> missing_fields {
        get; private set; default = new Gee.LinkedList<string>();
    }

    /** Constructs a new merge processor with the given template. */
    public Processor(Geary.Email template) {
        this.template = template;
    }

    /**
     * Merges the template with the given data to produce a complete message.
     *
     * Creates a new composed email based on the template and given
     * data, set it as the {@email} property and returns it.
     */
    public Geary.ComposedEmail merge(Gee.Map<string,string> values)
        throws GLib.Error {
        var from = format_mailbox_addresses(this.template.from, values);
        var email = this.email = new Geary.ComposedEmail(
            new GLib.DateTime.now(), from
        );
        email.set_to(format_mailbox_addresses(this.template.to, values));
        email.set_cc(format_mailbox_addresses(this.template.cc, values));
        email.set_bcc(format_mailbox_addresses(this.template.bcc, values));
        email.set_reply_to(format_mailbox_addresses(this.template.reply_to, values));
        email.set_sender(format_mailbox_address(this.template.sender, values));
        if (this.template.subject != null) {
            email.set_subject(
                format_string(this.template.subject.value, values)
            );
        }
        email.set_in_reply_to(this.template.in_reply_to);
        email.set_references(this.template.references);
        // Don't set the Message-ID since it should be per-recipient

        var message = this.template.get_message();
        if (message.has_plain_body()) {
            email.body_text = format_string(
                message.get_plain_body(false, null), values
            );
        }
        if (message.has_html_body()) {
            email.body_html = format_string(
                message.get_html_body(null), values
            );
        }

        return email;
    }

    private inline Geary.RFC822.MailboxAddresses? format_mailbox_addresses(
        Geary.RFC822.MailboxAddresses? addresses,
        Gee.Map<string,string> values
    ) {
        Geary.RFC822.MailboxAddresses? formatted = null;
        if (addresses != null && !addresses.is_empty) {
            formatted = new Geary.RFC822.MailboxAddresses();
            foreach (var addr in addresses) {
                formatted = formatted.merge_mailbox(
                    format_mailbox_address(addr, values)
                );
            }
        }
        return formatted;
    }

    private inline Geary.RFC822.MailboxAddress? format_mailbox_address(
        Geary.RFC822.MailboxAddress? address,
        Gee.Map<string,string> values
    ) {
        Geary.RFC822.MailboxAddress? formatted = null;
        if (address != null) {
            formatted = new Geary.RFC822.MailboxAddress(
                format_string(address.name, values),
                format_string(address.address, values)
            );
        }
        return formatted;
    }

    private inline string format_string(string? text,
                                        Gee.Map<string,string> values) {
        string? formatted = null;
        if (text != null) {
            var buf = new GLib.StringBuilder.sized(text.length);
            var parser = Parser(text);

            while (!parser.spent) {
                string? value = null;
                if (parser.at_field_start) {
                    var field = parser.read_field();
                    if (parser.at_field_end) {
                        // found end-of-field-delim, look it up
                        value = values.get(field);
                        if (value == null) {
                            this.missing_fields.add(field);
                            value = to_field(field);
                        }
                    } else {
                        // didn't find end-of-field-delim, treat as text
                        value = field;
                    }
                } else {
                    value = parser.read_text();
                }
                buf.append(value);
            }
            formatted = buf.str;
        }
        return formatted;
    }

}
