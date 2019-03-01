/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public enum Geary.Smtp.Command {
    HELO,
    EHLO,
    QUIT,
    HELP,
    NOOP,
    RSET,
    AUTH,
    MAIL,
    RCPT,
    DATA,
    STARTTLS;

    public string serialize() {
        switch (this) {
            case HELO:
                return "helo";

            case EHLO:
                return "ehlo";

            case QUIT:
                return "quit";

            case HELP:
                return "help";

            case NOOP:
                return "noop";

            case RSET:
                return "rset";

            case AUTH:
                return "AUTH";

            case MAIL:
                return "mail";

            case RCPT:
                return "rcpt";

            case DATA:
                return "data";

            case STARTTLS:
                return "STARTTLS";

            default:
                assert_not_reached();
        }
    }

    public static Command deserialize(string str) throws SmtpError {
        switch (Ascii.strdown(str)) {
            case "helo":
                return HELO;

            case "ehlo":
                return EHLO;

            case "quit":
                return QUIT;

            case "help":
                return HELP;

            case "noop":
                return NOOP;

            case "rset":
                return RSET;

            case "auth":
                return AUTH;

            case "mail":
                return MAIL;

            case "rcpt":
                return RCPT;

            case "data":
                return DATA;

            case "starttls":
                return STARTTLS;

            default:
                throw new SmtpError.PARSE_ERROR("Unknown command \"%s\"", str);
        }
    }
}

