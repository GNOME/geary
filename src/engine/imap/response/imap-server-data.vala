/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Email data sent from the server to client in response to a command or unsolicited.
 *
 * See [[http://tools.ietf.org/html/rfc3501#section-7.2]] for more information.
 */

public class Geary.Imap.ServerData : ServerResponse {
    public ServerDataType server_data_type { get; private set; }

    private ServerData(Tag tag, ServerDataType server_data_type, Quirks quirks) {
        base(tag, quirks);

        this.server_data_type = server_data_type;
    }

    /**
     * Converts the {@link RootParameters} into {@link ServerData}.
     *
     * The supplied root is "stripped" of its children.  This may happen even if an exception is
     * thrown.  It's recommended to use {@link is_server_data} prior to this call.
     */
    public ServerData.migrate(RootParameters root, Quirks quirks)
        throws ImapError {
        base.migrate(root, quirks);

        server_data_type = ServerDataType.from_response(this);
    }

    /**
     * Returns true if {@link RootParameters} is recognized by {@link ServerDataType.from_response}.
     */
    public static bool is_server_data(RootParameters root) {
        if (!root.has_tag())
            return false;

        try {
            ServerDataType.from_response(root);

            return true;
        } catch (ImapError ierr) {
            return false;
        }
    }

    /**
     * Parses the {@link ServerData} into {@link Capabilities}, if possible.
     *
     * @throws ImapError.INVALID if not a Capability.
     */
    public Capabilities get_capabilities(int revision) throws ImapError {
        if (this.server_data_type != ServerDataType.CAPABILITY)
            throw new ImapError.INVALID("Not CAPABILITY data: %s", to_string());

        var params = new StringParameter[this.size];
        int count = 0;
        for (int ctr = 1; ctr < size; ctr++) {
            StringParameter? param = get_if_string(ctr);
            if (param != null) {
                params[count++] = param;
            }
        }

        return new Capabilities(params[0:count], revision);
    }

    /**
     * Parses the {@link ServerData} into an {@link ServerDataType.EXISTS} value, if possible.
     *
     * @throws ImapError.INVALID if not EXISTS.
     */
    public int get_exists() throws ImapError {
        if (server_data_type != ServerDataType.EXISTS)
            throw new ImapError.INVALID("Not EXISTS data: %s", to_string());

        return get_as_string(1).as_int32(0);
    }

    /**
     * Parses the {@link ServerData} into an expunged {@link SequenceNumber}, if possible.
     *
     * @throws ImapError.INVALID if not an expunged MessageNumber.
     */
    public SequenceNumber get_expunge() throws ImapError {
        if (server_data_type != ServerDataType.EXPUNGE)
            throw new ImapError.INVALID("Not EXPUNGE data: %s", to_string());

        return new SequenceNumber.checked(get_as_string(1).as_int64());
    }

    /**
     * Parses the {@link ServerData} into {@link FetchedData}, if possible.
     *
     * @throws ImapError.INVALID if not FetchData.
     */
    public FetchedData get_fetch() throws ImapError {
        if (server_data_type != ServerDataType.FETCH)
            throw new ImapError.INVALID("Not FETCH data: %s", to_string());

        return FetchedData.decode(this);
    }

    /**
     * Parses the {@link ServerData} into {@link MailboxAttributes}, if possible.
     *
     * @throws ImapError.INVALID if not MailboxAttributes.
     */
    public MailboxAttributes get_flags() throws ImapError {
        if (server_data_type != ServerDataType.FLAGS)
            throw new ImapError.INVALID("Not FLAGS data: %s", to_string());

        return MailboxAttributes.from_list(get_as_list(2));
    }

    /**
     * Parses the {@link ServerData} into {@link MailboxInformation}, if possible.
     *
     * @throws ImapError.INVALID if not MailboxInformation.
     */
    public MailboxInformation get_list() throws ImapError {
        if (server_data_type != ServerDataType.LIST && server_data_type != ServerDataType.XLIST)
            throw new ImapError.INVALID("Not LIST/XLIST data: %s", to_string());

        return MailboxInformation.decode(this, true);
    }

    /**
     * Parses the {@link ServerData} into {@link MailboxInformation}, if possible.
     *
     * @throws ImapError.INVALID if not a NAMESPACE response.
     */
    public NamespaceResponse get_namespace() throws ImapError {
        if (server_data_type != ServerDataType.NAMESPACE)
            throw new ImapError.INVALID("Not NAMESPACE data: %s", to_string());

        return NamespaceResponse.decode(this);
    }

    /**
     * Parses the {@link ServerData} into a {@link ServerDataType.RECENT} value, if possible.
     *
     * @throws ImapError.INVALID if not a {@link ServerDataType.RECENT} value.
     */
    public int get_recent() throws ImapError {
        if (server_data_type != ServerDataType.RECENT)
            throw new ImapError.INVALID("Not RECENT data: %s", to_string());

        return get_as_string(1).as_int32(0);
    }

    /**
     * Parses the {@link ServerData} into a {@link ServerDataType.SEARCH} value, if possible.
     *
     * @throws ImapError.INVALID if not a {@link ServerDataType.SEARCH} value.
     */
    public int64[] get_search() throws ImapError {
        if (server_data_type != ServerDataType.SEARCH)
            throw new ImapError.INVALID("Not SEARCH data: %s", to_string());

        if (size <= 2)
            return new int64[0];

        int64[] results = new int64[size - 2];
        for (int ctr = 2; ctr < size; ctr++)
            results[ctr - 2] = get_as_string(ctr).as_int64(0);

        return results;
    }

    /**
     * Parses the {@link ServerData} into {@link StatusData}, if possible.
     *
     * @throws ImapError.INVALID if not {@link StatusData}.
     */
    public StatusData get_status() throws ImapError {
        if (server_data_type != ServerDataType.STATUS)
            throw new ImapError.INVALID("Not STATUS data: %s", to_string());

        return StatusData.decode(this);
    }
}

