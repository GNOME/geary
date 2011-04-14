/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public enum Geary.Imap.Status {
    OK,
    NO,
    BAD,
    PREAUTH,
    BYE;
    
    public string to_string() {
        switch (this) {
            case OK:
                return "ok";
            
            case NO:
                return "no";
            
            case BAD:
                return "bad";
            
            case PREAUTH:
                return "preauth";
            
            case BYE:
                return "bye";
            
            default:
                assert_not_reached();
        }
    }
    
    public static Status decode(string value) throws ImapError {
        switch (value.down()) {
            case "ok":
                return OK;
            
            case "no":
                return NO;
            
            case "bad":
                return BAD;
            
            case "preauth":
                return PREAUTH;
            
            case "bye":
                return BYE;
            
            default:
                throw new ImapError.PARSE_ERROR("Unrecognized status response \"%s\"", value);
        }
    }
    
    public static Status from_parameter(StringParameter strparam) throws ImapError {
        return decode(strparam.value);
    }
    
    public Parameter to_parameter() {
        return new StringParameter(to_string());
    }
    
    public void serialize(Serializer ser) throws Error {
        ser.push_string(to_string());
    }
}

