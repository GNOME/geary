/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A descriptor of what flavor of {@link ServerData} is found in the response.
 *
 * See [[http://tools.ietf.org/html/rfc3501#section-7.2]] for more information.
 */

public enum Geary.Imap.ServerDataType {
    CAPABILITY,
    EXISTS,
    EXPUNGE,
    FETCH,
    FLAGS,
    LIST,
    LSUB,
    RECENT,
    SEARCH,
    STATUS;
    
    public string to_string() {
        switch (this) {
            case CAPABILITY:
                return "capability";
            
            case EXISTS:
                return "exists";
            
            case EXPUNGE:
                return "expunge";
            
            case FETCH:
                return "fetch";
            
            case FLAGS:
                return "flags";
            
            case LIST:
                return "list";
            
            case LSUB:
                return "lsub";
            
            case RECENT:
                return "recent";
            
            case SEARCH:
                return "search";
            
            case STATUS:
                return "status";
            
            default:
                assert_not_reached();
        }
    }
    
    public static ServerDataType decode(string value) throws ImapError {
        switch (value.down()) {
            case "capability":
                return CAPABILITY;
            
            case "exists":
                return EXISTS;
            
            case "expunge":
            case "expunged":
                return EXPUNGE;
            
            case "fetch":
                return FETCH;
            
            case "flags":
                return FLAGS;
            
            case "list":
                return LIST;
            
            case "lsub":
                return LSUB;
            
            case "recent":
                return RECENT;
            
            case "search":
                return SEARCH;
            
            case "status":
                return STATUS;
            
            default:
                throw new ImapError.PARSE_ERROR("\"%s\" is not a valid server data type", value);
        }
    }
    
    public StringParameter to_parameter() {
        return new StringParameter(to_string());
    }
    
    /**
     * Convert a {@link StringParameter} into a ServerDataType.
     *
     * @throws ImapError.PARSE_ERROR if the StringParameter is not recognized as a ServerDataType.
     */
    public static ServerDataType from_parameter(StringParameter param) throws ImapError {
        return decode(param.value);
    }
    
    /**
     * Examines the {@link RootParameters} looking for a ServerDataType.
     *
     * IMAP server responses don't offer a regular format for server data declations.  This method
     * parses for the common patterns and returns the ServerDataType it detects.
     *
     * See [[http://tools.ietf.org/html/rfc3501#section-7.2]] for more information.
     */
    public static ServerDataType from_response(RootParameters root) throws ImapError {
        StringParameter? firstparam = root.get_if_string(1);
        if (firstparam != null) {
            switch (firstparam.value.down()) {
                case "capability":
                    return CAPABILITY;
                
                case "flags":
                    return FLAGS;
                
                case "list":
                    return LIST;
                
                case "lsub":
                    return LSUB;
                
                case "search":
                    return SEARCH;
                
                case "status":
                    return STATUS;
                
                default:
                    // fall-through
                break;
            }
        }
        
        StringParameter? secondparam = root.get_if_string(2);
        if (secondparam != null) {
            switch (secondparam.value.down()) {
                case "exists":
                    return EXISTS;
                
                case "expunge":
                case "expunged":
                    return EXPUNGE;
                
                case "fetch":
                    return FETCH;
                
                case "recent":
                    return RECENT;
                
                default:
                    // fall-through
                break;
            }
        }
        
        throw new ImapError.PARSE_ERROR("\"%s\" unrecognized server data", root.to_string());
    }
}

