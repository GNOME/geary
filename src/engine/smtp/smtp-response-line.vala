/* Copyright 2011-2012 Yorba Foundation
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
        
        // Only one of two separators allowed
        bool continued;
        if (line[ResponseCode.STRLEN] == NOT_CONTINUED_CHAR)
            continued = false;
        else if (line[ResponseCode.STRLEN] == CONTINUED_CHAR)
            continued = true;
        else
            throw new SmtpError.PARSE_ERROR("Invalid separator: %s", line);
        
        return new ResponseLine(new ResponseCode(line.substring(0, ResponseCode.STRLEN)),
            line.substring(ResponseCode.STRLEN + 1, -1), continued);
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

