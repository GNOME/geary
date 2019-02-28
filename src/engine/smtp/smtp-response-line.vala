/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class Geary.Smtp.ResponseLine {
    public const char CONTINUED_CHAR = '-';
    public const char NOT_CONTINUED_CHAR = ' ';

    public ResponseCode code { get; private set; }
    public string? explanation { get; private set; }
    public bool continued { get; private set; }

    public ResponseLine(ResponseCode code, string? explanation, bool continued) {
        this.code = code;
        this.explanation = explanation;
        this.continued = continued;
    }

    /**
     * Converts a serialized line into something usable.  The CRLF should *not* be included in
     * the input.
     */
    public static ResponseLine deserialize(string line) throws SmtpError {
        // the ResponseCode is mandatory
        if (line.length < ResponseCode.STRLEN)
            throw new SmtpError.PARSE_ERROR("Line too short: %s", line);

        // Only one of two separators allowed, as well as no separator (which means no explanation
        // and not continued)
        string? explanation;
        bool continued;
        switch (line[ResponseCode.STRLEN]) {
            case NOT_CONTINUED_CHAR:
                explanation = line.substring(ResponseCode.STRLEN + 1, -1);
                continued = false;
            break;

            case String.EOS:
                explanation = null;
                continued = false;
            break;

            case CONTINUED_CHAR:
                explanation = explanation = line.substring(ResponseCode.STRLEN + 1, -1);
                continued = true;
            break;

            default:
                throw new SmtpError.PARSE_ERROR("Invalid response line separator: %s", line);
        }

        return new ResponseLine(new ResponseCode(line.substring(0, ResponseCode.STRLEN)),
            explanation, continued);
    }

    /**
     * Serializes the Reply into a line for transmission.  Note that the CRLF is *not* included.
     */
    public string serialize() {
        return "%s%c%s".printf(
            code.serialize(),
            continued ? CONTINUED_CHAR : NOT_CONTINUED_CHAR,
            explanation ?? "");
    }

    public string to_string() {
        return serialize();
    }
}

