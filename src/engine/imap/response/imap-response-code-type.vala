/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * An optional response code accompanying a {@link ServerResponse}.
 *
 * See [[http://tools.ietf.org/html/rfc3501#section-7.1]] for more information.
 */

public enum Geary.Imap.ResponseCodeType {
    ALERT,
    AUTHENTICATIONFAILED,
    AUTHORIZATIONFAILED,
    BADCHARSET,
    CAPABILITY,
    NEWNAME,
    PARSE,
    PERMANENT_FLAGS,
    READONLY,
    READWRITE,
    TRY_CREATE,
    UIDVALIDITY,
    UIDNEXT,
    UNSEEN,
    MYRIGHTS,
    UNAVAILABLE,
    SERVERBUG,
    CLIENTBUG,
    ALREADYEXISTS,
    NONEXISTANT;
    
    public string to_string() {
        switch (this) {
            case ALERT:
                return "alert";
            
            case AUTHENTICATIONFAILED:
                return "authenticationfailed";
            
            case AUTHORIZATIONFAILED:
                return "authorizationfailed";
            
            case BADCHARSET:
                return "badcharset";
            
            case CAPABILITY:
                return "capability";
            
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
            
            case UNAVAILABLE:
                return "unavailable";
            
            case SERVERBUG:
                return "serverbug";
            
            case CLIENTBUG:
                return "clientbug";
            
            case ALREADYEXISTS:
                return "alreadyexists";
            
            case NONEXISTANT:
                return "nonexistant";
            
            default:
                assert_not_reached();
        }
    }
    
    public static ResponseCodeType decode(string value) throws ImapError {
        switch (value.down()) {
            case "alert":
                return ALERT;
            
            case "authenticationfailed":
                return AUTHENTICATIONFAILED;
            
            case "authorizationfailed":
                return AUTHORIZATIONFAILED;
            
            case "badcharset":
                return BADCHARSET;
            
            case "capability":
                return CAPABILITY;
            
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
            
            case "unavailable":
                return UNAVAILABLE;
            
            case "serverbug":
                return SERVERBUG;
            
            case "clientbug":
                return CLIENTBUG;
            
            case "alreadyexists":
                return ALREADYEXISTS;
            
            case "nonexistant":
                return NONEXISTANT;
            
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

