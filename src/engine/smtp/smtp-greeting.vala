/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class Geary.Smtp.Greeting : Response {
    public enum ServerFlavor {
        SMTP,
        ESMTP,
        UNSPECIFIED;

        /**
         * Returns an empty string if UNSPECIFIED.
         */
        public string serialize() {
            switch (this) {
                case SMTP:
                    return "SMTP";

                case ESMTP:
                    return "ESMTP";

                default:
                    return "";
            }
        }

        public static ServerFlavor deserialize(string str) {
            switch (Ascii.strup(str)) {
                case "SMTP":
                    return SMTP;

                case "ESMTP":
                    return ESMTP;

                default:
                    return UNSPECIFIED;
            }
        }
    }

    public string? domain { get; private set; default = null; }
    public ServerFlavor flavor { get; private set; default = ServerFlavor.UNSPECIFIED; }
    public string? message { get; private set; default = null; }

    public Greeting(Gee.List<ResponseLine> lines) {
        base (lines);

        // tokenize first line explanation for domain, server flavor, and greeting message
        if (!String.is_empty(first_line.explanation)) {
            string[] tokens = first_line.explanation.substring(ResponseCode.STRLEN + 1, -1).split(" ");
            int length = tokens.length;
            int index = 0;

            if (index < length)
                domain = tokens[index++];

            if (index < length) {
                string f = tokens[index++];
                flavor = ServerFlavor.deserialize(f);
                if (flavor == ServerFlavor.UNSPECIFIED) {
                    // actually part of the message, not a flavor
                    message = f;
                }
            }

            while (index < length) {
                if (String.is_empty(message))
                    message = tokens[index++];
                else
                    message += " " + tokens[index++];
            }
        }
    }
}

