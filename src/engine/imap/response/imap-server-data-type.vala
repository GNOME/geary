/* Copyright 2016 Software Freedom Conservancy Inc.
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
    NAMESPACE,
    RECENT,
    SEARCH,
    STATUS,
    XLIST;

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

            case NAMESPACE:
                return "namespace";

            case RECENT:
                return "recent";

            case SEARCH:
                return "search";

            case STATUS:
                return "status";

            case XLIST:
                return "xlist";

            default:
                assert_not_reached();
        }
    }

    /**
     * Convert a {@link StringParameter} into a ServerDataType.
     *
     * @throws ImapError.PARSE_ERROR if the StringParameter is not recognized as a ServerDataType.
     */
    public static ServerDataType from_parameter(StringParameter param) throws ImapError {
        switch (param.as_lower()) {
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

            case "namespace":
                return NAMESPACE;

            case "recent":
                return RECENT;

            case "search":
                return SEARCH;

            case "status":
                return STATUS;

            case "xlist":
                return XLIST;

            default:
                throw new ImapError.PARSE_ERROR("\"%s\" is not a valid server data type", param.to_string());
        }
    }

    public StringParameter to_parameter() {
        return new AtomParameter(to_string());
    }

    /**
     * Examines the {@link RootParameters} looking for a ServerDataType.
     *
     * IMAP server responses don't offer a regular format for server data declaretions.  This method
     * parses for the common patterns and returns the ServerDataType it detects.
     *
     * See [[http://tools.ietf.org/html/rfc3501#section-7.2]] for more information.
     */
    public static ServerDataType from_response(RootParameters root) throws ImapError {
        StringParameter? firstparam = root.get_if_string(1);
        if (firstparam != null) {
            switch (firstparam.as_lower()) {
                case "capability":
                    return CAPABILITY;

                case "flags":
                    return FLAGS;

                case "list":
                    return LIST;

                case "lsub":
                    return LSUB;

                case "namespace":
                    return NAMESPACE;

                case "search":
                    return SEARCH;

                case "status":
                    return STATUS;

                case "xlist":
                    return XLIST;

                default:
                    // fall-through
                break;
            }
        }

        StringParameter? secondparam = root.get_if_string(2);
        if (secondparam != null) {
            switch (secondparam.as_lower()) {
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

