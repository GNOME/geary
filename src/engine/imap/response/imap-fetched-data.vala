/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * The deserialized representation of a FETCH response.
 *
 * See [[http://tools.ietf.org/html/rfc3501#section-7.4.2]]
 *
 * @see FetchCommand
 * @see StoreCommand
 */
public class Geary.Imap.FetchedData : Object {
    /**
     * The positional address of the email in the mailbox.
     */
    public SequenceNumber seq_num { get; private set; }

    /**
     * A Map of {@link FetchDataSpecifier}s to their {@link Imap.MessageData} for this email.
     *
     * MessageData should be cast to their appropriate class depending on their FetchDataSpecifier.
     */
    public Gee.Map<FetchDataSpecifier, MessageData> data_map { get; private set;
        default = new Gee.HashMap<FetchDataSpecifier, MessageData>(); }

    /**
     * List of {@link FetchBodyDataSpecifier} responses.
     */
    public Gee.Map<FetchBodyDataSpecifier, Memory.Buffer> body_data_map { get; private set;
        default = new Gee.HashMap<FetchBodyDataSpecifier, Memory.Buffer>(); }

    public FetchedData(SequenceNumber seq_num) {
        this.seq_num = seq_num;
    }

    /**
     * Decodes {@link ServerData} into a FetchedData representation.
     *
     * The ServerData must be the response to a FETCH or STORE command.
     *
     * @see FetchCommand
     * @see StoreCommand
     * @see ServerData.get_fetch
     */
    public static FetchedData decode(ServerData server_data) throws ImapError {
        if (!server_data.get_as_string(2).equals_ci(FetchCommand.NAME))
            throw new ImapError.PARSE_ERROR("Not FETCH data: %s", server_data.to_string());

        FetchedData fetched_data = new FetchedData(
            new SequenceNumber.checked(server_data.get_as_string(1).as_int64()));

        // walk the list for each returned fetch data item, which is paired by its data item name
        // and the structured data itself
        ListParameter list = server_data.get_as_list(3);
        for (int ctr = 0; ctr < list.size; ctr += 2) {
            StringParameter data_item_param = list.get_as_string(ctr);

            // watch for truncated lists, which indicate an empty return value
            bool has_value = (ctr < (list.size - 1));

            if (FetchBodyDataSpecifier.is_fetch_body_data_specifier(data_item_param)) {
                // "fake" the identifier by merely dropping in the StringParameter wholesale ...
                // this works because FetchBodyDataIdentifier does case-insensitive comparisons ...
                // other munging may be required if this isn't sufficient
                FetchBodyDataSpecifier specifier = FetchBodyDataSpecifier.deserialize_response(data_item_param);

                if (has_value)
                    fetched_data.body_data_map.set(specifier, list.get_as_empty_buffer(ctr + 1));
                else
                    fetched_data.body_data_map.set(specifier, Memory.EmptyBuffer.instance);
            } else {
                FetchDataSpecifier data_item = FetchDataSpecifier.from_parameter(data_item_param);
                FetchDataDecoder? decoder = data_item.get_decoder(server_data.quirks);
                if (decoder == null) {
                    debug("Unable to decode fetch response for \"%s\": No decoder available",
                        data_item.to_string());

                    continue;
                }

                // watch for empty return values
                if (has_value)
                    fetched_data.data_map.set(data_item, decoder.decode(list.get_required(ctr + 1)));
                else
                    fetched_data.data_map.set(data_item, decoder.decode(NilParameter.instance));
            }
        }

        return fetched_data;
    }

    /**
     * Returns the merge of this {@link FetchedData} and the supplied one.
     *
     * The results are undefined if both FetchData objects contain the same
     * {@link FetchDataSpecifier} or {@link FetchBodyDataSpecifier}s.
     *
     * See warnings at {@link body_data_map} for dealing with multiple FetchBodyDataSpecifiers.
     *
     * @return null if the FetchedData do not have the same {@link seq_num}.
     */
    public FetchedData? combine(FetchedData other) {
        if (!seq_num.equal_to(other.seq_num))
            return null;

        FetchedData combined = new FetchedData(seq_num);
        Collection.map_set_all<FetchDataSpecifier, MessageData>(combined.data_map, data_map);
        Collection.map_set_all<FetchDataSpecifier, MessageData>(combined.data_map, other.data_map);
        Collection.map_set_all<FetchBodyDataSpecifier, Memory.Buffer>(combined.body_data_map,
            body_data_map);
        Collection.map_set_all<FetchBodyDataSpecifier, Memory.Buffer>(combined.body_data_map,
            other.body_data_map);

        return combined;
    }

    public string to_string() {
        StringBuilder builder = new StringBuilder();

        builder.append_printf("[%s] ", seq_num.to_string());

        foreach (FetchDataSpecifier data_type in data_map.keys)
            builder.append_printf("%s=%s ", data_type.to_string(), data_map.get(data_type).to_string());

        foreach (FetchBodyDataSpecifier specifier in body_data_map.keys)
            builder.append_printf("%s=%lu ", specifier.to_string(), body_data_map.get(specifier).size);

        return builder.str;
    }
}

