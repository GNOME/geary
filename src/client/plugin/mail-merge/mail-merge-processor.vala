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


    public const Geary.Email.Field REQUIRED_FIELDS =
        Geary.Email.REQUIRED_FOR_MESSAGE;


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

}
