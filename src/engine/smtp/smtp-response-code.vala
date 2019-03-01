/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class Geary.Smtp.ResponseCode {
    public const int STRLEN = 3;

    public const int MIN = 100;
    public const int MAX = 599;

    public const string START_DATA_CODE = "354";
    public const string STARTTLS_READY_CODE = "220";
    public const string DENIED_CODE = "550";

    public enum Status {
        POSITIVE_PRELIMINARY = 1,
        POSITIVE_COMPLETION = 2,
        POSITIVE_INTERMEDIATE = 3,
        TRANSIENT_NEGATIVE = 4,
        PERMANENT_FAILURE = 5,
        UNKNOWN = -1;
    }

    public enum Condition {
        SYNTAX = 0,
        ADDITIONAL_INFO = 1,
        COMM_CHANNEL = 2,
        MAIL_SYSTEM = 5,
        UNKNOWN = -1
    }

    private string str;

    public ResponseCode(string str) throws SmtpError {
        // these two checks are sufficient to make sure the Status is valid, but not the Condition
        if (str.length != STRLEN)
            throw new SmtpError.PARSE_ERROR("Reply code wrong length: %s (%d)", str, str.length);

        int as_int = int.parse(str);
        if (as_int < MIN || as_int > MAX)
            throw new SmtpError.PARSE_ERROR("Reply code out of range: %s", str);

        this.str = str;
    }

    public Status get_status() {
        int i = Ascii.digit_to_int(str[0]);

        // This works because of the checks in the constructor; Condition can't be checked so
        // easily
        return (i != -1) ? (Status) i : Status.UNKNOWN;
    }

    public Condition get_condition() {
        switch (Ascii.digit_to_int(str[1])) {
            case Condition.SYNTAX:
                return Condition.SYNTAX;

            case Condition.ADDITIONAL_INFO:
                return Condition.ADDITIONAL_INFO;

            case Condition.COMM_CHANNEL:
                return Condition.COMM_CHANNEL;

            case Condition.MAIL_SYSTEM:
                return Condition.MAIL_SYSTEM;

            default:
                return Condition.UNKNOWN;
        }
    }

    public bool is_success_completed() {
        return get_status() == Status.POSITIVE_COMPLETION;
    }

    public bool is_success_intermediate() {
        switch (get_status()) {
            case Status.POSITIVE_PRELIMINARY:
            case Status.POSITIVE_INTERMEDIATE:
                return true;

            default:
                return false;
        }
    }

    public bool is_failure() {
        switch (get_status()) {
            case Status.PERMANENT_FAILURE:
            case Status.TRANSIENT_NEGATIVE:
                return true;

            default:
                return false;
        }
    }

    public bool is_start_data() {
        return str == START_DATA_CODE;
    }

    public bool is_starttls_ready() {
        return str == STARTTLS_READY_CODE;
    }

    public bool is_denied() {
        return str == DENIED_CODE;
    }

    /**
     * Returns true for [@link Status.PERMANENT_FAILURE} {@link Condition.SYNTAX} errors.
     *
     * Generally this means the command (or sequence of commands) was unknown or unimplemented,
     * i.e. "500 Syntax error", "502 Command not implemented", etc.
     *
     * See [[http://tools.ietf.org/html/rfc5321#section-4.2.2]]
     */
    public bool is_syntax_error() {
        return get_status() == ResponseCode.Status.PERMANENT_FAILURE
            && get_condition() == ResponseCode.Condition.SYNTAX;
    }

    public string serialize() {
        return str;
    }

    public string to_string() {
        return str;
    }
}

