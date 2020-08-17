/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A response line from the server indicating either a result from a command or an unsolicited
 * change in state.
 *
 * StatusResponses may be tagged or untagged, depending on their nature.
 *
 * See [[http://tools.ietf.org/html/rfc3501#section-7.1]] for more information.
 */

public class Geary.Imap.StatusResponse : ServerResponse {
    /**
     * Returns true if this {@link StatusResponse} represents the completion of a {@link Command}.
     *
     * This is true if (a) the StatusResponse is tagged and (b) the {@link status} is
     * {@link Status.OK}, {@link Status.NO}, or {@link Status.BAD}.
     */
    public bool is_completion { get; private set; default = false; }

    /**
     * The {@link Status} being reported by the server in this {@link ServerResponse}.
     */
    public Status status { get; private set; }

    /**
     * An optional {@link ResponseCode} reported by the server in this {@link ServerResponse}.
     */
    public ResponseCode? response_code { get; private set; }

    private StatusResponse(Tag tag,
                           Status status,
                           ResponseCode? response_code,
                           Quirks quirks) {
        base(tag, quirks);

        this.status = status;
        this.response_code = response_code;
        update_is_completion();
    }

    /**
     * Converts the {@link RootParameters} into a {@link StatusResponse}.
     *
     * The supplied root is "stripped" of its children.  This may happen even if an exception is
     * thrown.  It's recommended to use {@link is_status_response} prior to this call.
     */
    public StatusResponse.migrate(RootParameters root, Quirks quirks)
        throws ImapError {
            base.migrate(root, quirks);

        status = Status.from_parameter(get_as_string(1));
        response_code = get_if_list(2) as ResponseCode;
        update_is_completion();
    }

    private void update_is_completion() {
        // TODO: Is this too stringent?  It means a faulty server could send back a completion
        // with another Status code and cause the client to treat the command as "unanswered",
        // requiring a timeout.
        is_completion = false;
        if (tag.is_tagged()) {
            switch (status) {
                case Status.OK:
                case Status.NO:
                case Status.BAD:
                    is_completion = true;
                break;

                default:
                    // fall through
                break;
            }
        }
    }

    /**
     * Returns optional text provided by the server.  Note that this text is not internationalized
     * and probably in English, and is not standard or uniformly declared.  It's not recommended
     * this text be displayed to the user.
     */
    public string? get_text() {
        // build text from all StringParameters ... this will skip any ResponseCode or ListParameter
        // (or NilParameter, for that matter)
        StringBuilder builder = new StringBuilder();
        for (int index = 2; index < size; index++) {
            StringParameter? strparam = get_if_string(index);
            if (strparam != null) {
                builder.append(strparam.ascii);
                if (index < (size - 1))
                    builder.append_c(' ');
            }
        }

        return !String.is_empty(builder.str) ? builder.str : null;
    }

    /**
     * Returns true if {@link RootParameters} holds a {@link Status} parameter.
     */
    public static bool is_status_response(RootParameters root) {
        if (!root.has_tag())
            return false;

        try {
            Status.from_parameter(root.get_as_string(1));

            return true;
        } catch (ImapError err) {
            return false;
        }
    }
}

