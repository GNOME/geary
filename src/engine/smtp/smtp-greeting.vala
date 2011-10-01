/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Smtp.Greeting {
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
            switch (str.up()) {
                case "SMTP":
                    return SMTP;
                
                case "ESMTP":
                    return ESMTP;
                
                default:
                    return UNSPECIFIED;
            }
        }
    }
    
    public ResponseCode code { get; private set; }
    public string? domain { get; private set; }
    public ServerFlavor flavor { get; private set; }
    public string? message { get; private set; }
    
    public Greeting(ResponseCode code, string? domain, ServerFlavor flavor, string? message) {
        this.code = code;
        this.domain = domain;
        this.flavor = flavor;
        this.message = message;
    }
    
    /**
     * Converts the first serialized line from a server into something usable.  The CRLF should
     * *not* be included in the input.
     */
    public static Greeting deserialize(string line) throws SmtpError {
        // ResponseCode is mandatory
        if (line.length < ResponseCode.STRLEN)
            throw new SmtpError.PARSE_ERROR("Greeting too short: %s", line);
        
        // tokenize by spaces; must be at least one
        string[] tokens = line.split(" ");
        int length = tokens.length;
        if (length < 1)
            throw new SmtpError.PARSE_ERROR("Invalid greeting: %s", line);
        
        // assemble the parameters
        ResponseCode code = new ResponseCode(tokens[0]);
        
        int index = 1;
        string? domain = null;
        ServerFlavor flavor = ServerFlavor.UNSPECIFIED;
        string? message = null;
        
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
        
        return new Greeting(code, domain, flavor, message);
    }
    
    public string serialize() {
        StringBuilder builder = new StringBuilder();
        
        builder.append(code.serialize());
        
        if (!String.is_empty(domain)) {
            builder.append_c(' ');
            builder.append(domain);
        }
        
        if (flavor != ServerFlavor.UNSPECIFIED) {
            builder.append_c(' ');
            builder.append(flavor.serialize());
        }
        
        if (!String.is_empty(message)) {
            builder.append_c(' ');
            builder.append(message);
        }
        
        return builder.str;
    }
    
    public string to_string() {
        return serialize();
    }
}

