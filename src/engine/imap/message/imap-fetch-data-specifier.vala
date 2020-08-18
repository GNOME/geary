/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A symbolic representation of IMAP FETCH's specifier parameter.
 *
 * Most FETCH requests can use this simple specifier to return various parts of the message.
 * More complicated requests (and requests for partial header or body sections) must use a
 * {@link FetchBodyDataSpecifier} specifier.
 *
 * See [[http://tools.ietf.org/html/rfc3501#section-6.4.5]]
 *
 * @see FetchBodyDataSpecifier
 */

public enum Geary.Imap.FetchDataSpecifier {
    UID,
    FLAGS,
    INTERNALDATE,
    ENVELOPE,
    BODYSTRUCTURE,
    BODY,
    RFC822,
    RFC822_HEADER,
    RFC822_SIZE,
    RFC822_TEXT,
    FAST,
    ALL,
    FULL;

    public string to_string() {
        switch (this) {
            case UID:
                return "uid";

            case FLAGS:
                return "flags";

            case INTERNALDATE:
                return "internaldate";

            case ENVELOPE:
                return "envelope";

            case BODYSTRUCTURE:
                return "bodystructure";

            case BODY:
                return "body";

            case RFC822:
                return "rfc822";

            case RFC822_HEADER:
                return "rfc822.header";

            case RFC822_SIZE:
                return "rfc822.size";

            case RFC822_TEXT:
                return "rfc822.text";

            case FAST:
                return "fast";

            case ALL:
                return "all";

            case FULL:
                return "full";

            default:
                assert_not_reached();
        }
    }

    /**
     * Decodes a {@link StringParameter} into a {@link FetchDataSpecifier}.
     */
    public static FetchDataSpecifier from_parameter(StringParameter strparam) throws ImapError {
        switch (strparam.as_lower()) {
            case "uid":
                return UID;

            case "flags":
                return FLAGS;

            case "internaldate":
                return INTERNALDATE;

            case "envelope":
                return ENVELOPE;

            case "bodystructure":
                return BODYSTRUCTURE;

            case "body":
                return BODY;

            case "rfc822":
                return RFC822;

            case "rfc822.header":
                return RFC822_HEADER;

            case "rfc822.size":
                return RFC822_SIZE;

            case "rfc822.text":
                return RFC822_TEXT;

            case "fast":
                return FAST;

            case "all":
                return ALL;

            case "full":
                return FULL;

            default:
                throw new ImapError.PARSE_ERROR("\"%s\" is not a valid fetch-command data item",
                    strparam.to_string());
        }
    }

    /**
     * Turns this {@link FetchDataSpecifier} into a {@link StringParameter} for transmission.
     */
    public StringParameter to_parameter() {
        return new AtomParameter(to_string());
    }

    /**
     * Returns the appropriate {@link FetchDataDecoder} for this {@link FetchDataSpecifier}.
     *
     * The FetchDataDecoder can then be used to convert the associated {@link Parameter}s into
     * {@link Imap.MessageData}.
     *
     * @return null if no FetchDataDecoder is associated with this value, or an invalid value.
     */
    public FetchDataDecoder? get_decoder(Quirks quirks) {
        switch (this) {
            case UID:
                return new UIDDecoder();

            case FLAGS:
                return new MessageFlagsDecoder();

            case ENVELOPE:
                return new EnvelopeDecoder(quirks);

            case INTERNALDATE:
                return new InternalDateDecoder();

            case RFC822_SIZE:
                return new RFC822SizeDecoder();

            case RFC822_HEADER:
                return new RFC822HeaderDecoder();

            case RFC822_TEXT:
                return new RFC822TextDecoder();

            case RFC822:
                return new RFC822FullDecoder();

            default:
                return null;
        }
    }
}

