/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A representation of the IMAP FETCH command.
 *
 * FETCH is easily the most complicated IMAP command.  It has a large number of parameters, some of
 * which have a number of variants, others defined as macros combining other fields, and the
 * returned {@link ServerData} requires involved decoding patterns.
 *
 * See [[http://tools.ietf.org/html/rfc3501#section-6.4.5]]
 *
 * @see FetchedData
 * @see StoreCommand
 */
public class Geary.Imap.FetchCommand : Command {

    public const string NAME = "fetch";
    public const string UID_NAME = "uid fetch";

    /**
     * Non-null if {@link FetchCommand} created for this {@link FetchDataSpecifier}.
     */
    public Gee.List<FetchDataSpecifier> for_data_types { get; private set;
        default = new Gee.ArrayList<FetchDataSpecifier>(); }

    /**
     * Non-null if {@link FetchCommand} created for this {@link FetchBodyDataSpecifier}.
     */
    public Gee.List<FetchBodyDataSpecifier> for_body_data_specifiers { get; private set;
        default = new Gee.ArrayList<FetchBodyDataSpecifier>(); }

    public FetchCommand(MessageSet msg_set,
                        Gee.List<FetchDataSpecifier>? data_items,
                        Gee.List<FetchBodyDataSpecifier>? body_data_items,
                        GLib.Cancellable? should_send) {
        base(msg_set.is_uid ? UID_NAME : NAME, null, should_send);

        this.args.add(msg_set.to_parameter());

        int data_items_length = (data_items != null) ? data_items.size : 0;
        int body_items_length = (body_data_items != null) ? body_data_items.size : 0;

        // see note in unadorned ctor for reasoning here
        if (data_items_length == 1 && body_items_length == 0) {
            this.args.add(data_items[0].to_parameter());
        } else if (data_items_length == 0 && body_items_length == 1) {
            this.args.add(body_data_items[0].to_request_parameter());
        } else {
            ListParameter list = new ListParameter();

            if (data_items_length > 0) {
                foreach (FetchDataSpecifier data_item in data_items)
                    list.add(data_item.to_parameter());
            }

            if (body_items_length > 0) {
                foreach (FetchBodyDataSpecifier body_item in body_data_items)
                    list.add(body_item.to_request_parameter());
            }

            this.args.add(list);
        }

        if (data_items != null)
            for_data_types.add_all(data_items);

        if (body_data_items != null)
            for_body_data_specifiers.add_all(body_data_items);
    }

    public FetchCommand.data_type(MessageSet msg_set,
                                  FetchDataSpecifier data_type,
                                  GLib.Cancellable? should_send) {
        base(msg_set.is_uid ? UID_NAME : NAME, null, should_send);

        for_data_types.add(data_type);

        this.args.add(msg_set.to_parameter());
        this.args.add(data_type.to_parameter());
    }

    public FetchCommand.body_data_type(MessageSet msg_set,
                                       FetchBodyDataSpecifier body_data_specifier,
                                       GLib.Cancellable? should_send) {
        base(msg_set.is_uid ? UID_NAME : NAME, null, should_send);

        for_body_data_specifiers.add(body_data_specifier);

        this.args.add(msg_set.to_parameter());
        this.args.add(body_data_specifier.to_request_parameter());
    }

}
