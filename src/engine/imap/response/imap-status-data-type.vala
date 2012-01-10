/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public enum Geary.Imap.StatusDataType {
    MESSAGES,
    RECENT,
    UIDNEXT,
    UIDVALIDITY,
    UNSEEN;
    
    public static StatusDataType[] all() {
        return { MESSAGES, RECENT, UIDNEXT, UIDVALIDITY, UNSEEN };
    }
    
    public string to_string() {
        switch (this) {
            case MESSAGES:
                return "messages";
            
            case RECENT:
                return "recent";
            
            case UIDNEXT:
                return "uidnext";
            
            case UIDVALIDITY:
                return "uidvalidity";
            
            case UNSEEN:
                return "unseen";
            
            default:
                assert_not_reached();
        }
    }
    
    public static StatusDataType decode(string value) throws ImapError {
        switch (value.down()) {
            case "messages":
                return MESSAGES;
            
            case "recent":
                return RECENT;
            
            case "uidnext":
                return UIDNEXT;
            
            case "uidvalidity":
                return UIDVALIDITY;
            
            case "unseen":
                return UNSEEN;
            
            default:
                throw new ImapError.PARSE_ERROR("Unknown status data type \"%s\"", value);
        }
    }
    
    public StringParameter to_parameter() {
        return new StringParameter(to_string());
    }
    
    public static StatusDataType from_parameter(StringParameter stringp) throws ImapError {
        return decode(stringp.value);
    }
}

