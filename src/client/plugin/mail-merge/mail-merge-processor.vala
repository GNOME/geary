/*
 * Copyright © 2020 Michael Gratton <mike@vee.net>.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * Substitutes merge fields in an email with actual data.
 */
public class Plugin.MailMergeProcessor : GLib.Object {


    public const Geary.Email.Field REQUIRED_FIELDS =
        Geary.Email.REQUIRED_FOR_MESSAGE;


    private const string FIELD_START = "{{";
    private const string FIELD_END = "}}";


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

    private static bool contains_field(string value) {
        var found = false;
        var index = 0;
        while (!found) {
            var field_start = value.index_of(FIELD_START, index);
            if (field_start < 0) {
                break;
            }
            found = parse_field((string) value.data[field_start:-1]) != null;
            index = field_start + 1;
        }
        return found;
    }

    private static string? parse_field(string value) {
        string? field = null;
        if (value.has_prefix(FIELD_START)) {
            int start = FIELD_START.length;
            int end = value.index_of(FIELD_END, start);
            if (end >= 0) {
                field = value.substring(start, end - FIELD_END.length).strip();
            }
        }
        return field;
    }

}
