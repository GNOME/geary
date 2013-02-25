/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public enum Geary.Imap.ResponseCodeType {
    ALERT,
    NEWNAME,
    PARSE,
    PERMANENT_FLAGS,
    READONLY,
    READWRITE,
    TRY_CREATE,
    UIDVALIDITY,
    UIDNEXT,
    UNSEEN,
    MYRIGHTS;
    
    public string to_string() {
        switch (this) {
            case ALERT:
                return "alert";
            
            case NEWNAME:
                return "newname";
            
            case PARSE:
                return "parse";
            
            case PERMANENT_FLAGS:
                return "permanentflags";
            
            case READONLY:
                return "read-only";
            
            case READWRITE:
                return "read-write";
            
            case TRY_CREATE:
                return "trycreate";
            
            case UIDVALIDITY:
                return "uidvalidity";
            
            case UIDNEXT:
                return "uidnext";
            
            case UNSEEN:
                return "unseen";
            
            case MYRIGHTS:
                return "myrights";
            
            default:
                assert_not_reached();
        }
    }
    
    public static ResponseCodeType decode(string value) throws ImapError {
        switch (value.down()) {
            case "alert":
                return ALERT;
            
            case "newname":
                return NEWNAME;
            
            case "parse":
                return PARSE;
            
            case "permanentflags":
                return PERMANENT_FLAGS;
            
            case "read-only":
                return READONLY;
            
            case "read-write":
                return READWRITE;
            
            case "trycreate":
                return TRY_CREATE;
            
            case "uidvalidity":
                return UIDVALIDITY;
            
            case "uidnext":
                return UIDNEXT;
            
            case "unseen":
                return UNSEEN;
            
            case "myrights":
                return MYRIGHTS;
            
            default:
                throw new ImapError.PARSE_ERROR("Unknown response code \"%s\"", value);
        }
    }
    
    public static ResponseCodeType from_parameter(StringParameter stringp) throws ImapError {
        return decode(stringp.value);
    }
    
    public StringParameter to_parameter() {
        return new StringParameter(to_string());
    }
}

