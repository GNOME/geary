/* Copyright 2017 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

namespace Geary.Config {
    public const string GROUP = "AccountInformation";
    public const string REAL_NAME_KEY = "real_name";
    public const string NICKNAME_KEY = "nickname";
    public const string PRIMARY_EMAIL_KEY = "primary_email";
    public const string ALTERNATE_EMAILS_KEY = "alternate_emails";
    public const string SERVICE_PROVIDER_KEY = "service_provider";
    public const string ORDINAL_KEY = "ordinal";
    public const string PREFETCH_PERIOD_DAYS_KEY = "prefetch_period_days";
    public const string IMAP_USERNAME_KEY = "imap_username";
    public const string IMAP_REMEMBER_PASSWORD_KEY = "imap_remember_password";
    public const string SMTP_USERNAME_KEY = "smtp_username";
    public const string SMTP_REMEMBER_PASSWORD_KEY = "smtp_remember_password";
    public const string IMAP_HOST = "imap_host";
    public const string IMAP_PORT = "imap_port";
    public const string IMAP_SSL = "imap_ssl";
    public const string IMAP_STARTTLS = "imap_starttls";
    public const string SMTP_HOST = "smtp_host";
    public const string SMTP_PORT = "smtp_port";
    public const string SMTP_SSL = "smtp_ssl";
    public const string SMTP_STARTTLS = "smtp_starttls";
    public const string SMTP_USE_IMAP_CREDENTIALS = "smtp_use_imap_credentials";
    public const string SMTP_NOAUTH = "smtp_noauth";
    public const string SAVE_SENT_MAIL_KEY = "save_sent_mail";
    public const string DRAFTS_FOLDER_KEY = "drafts_folder";
    public const string SENT_MAIL_FOLDER_KEY = "sent_mail_folder";
    public const string SPAM_FOLDER_KEY = "spam_folder";
    public const string TRASH_FOLDER_KEY = "trash_folder";
    public const string ARCHIVE_FOLDER_KEY = "archive_folder";
    public const string SAVE_DRAFTS_KEY = "save_drafts";
    public const string USE_EMAIL_SIGNATURE_KEY = "use_email_signature";
    public const string EMAIL_SIGNATURE_KEY = "email_signature";

    public static string get_string_value(KeyFile key_file, string group, string key, string def = "") {
        try {
            return key_file.get_value(group, key);
        } catch(KeyFileError err) {
            // Ignore.
        }

        return def;
    }

    public static string get_escaped_string(KeyFile key_file, string group, string key, string def = "") {
        try {
            return key_file.get_string(group, key);
        } catch (KeyFileError err) {
            // ignore
        }

        return def;
    }

    public static Gee.List<string> get_string_list_value(KeyFile key_file, string group, string key) {
        try {
            string[] list = key_file.get_string_list(group, key);
            if (list.length > 0)
                return Geary.Collection.array_list_wrap<string>(list);
        } catch(KeyFileError err) {
            // Ignore.
        }

        return new Gee.ArrayList<string>();
    }

    public static bool get_bool_value(KeyFile key_file, string group, string key, bool def = false) {
        try {
            return key_file.get_boolean(group, key);
        } catch(KeyFileError err) {
            // Ignore.
        }

        return def;
    }

    public static int get_int_value(KeyFile key_file, string group, string key, int def = 0) {
        try {
            return key_file.get_integer(group, key);
        } catch(KeyFileError err) {
            // Ignore.
        }

        return def;
    }

    public static uint16 get_uint16_value(KeyFile key_file, string group, string key, uint16 def = 0) {
        return (uint16) get_int_value(key_file, group, key);
    }
}
