/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * The IMAP STATUS command.
 *
 * See [[http://tools.ietf.org/html/rfc3501#section-6.3.10]]
 *
 * @see StatusData
 */
public class Geary.Imap.StatusCommand : Command {


    public const string NAME = "STATUS";


    public StatusCommand(MailboxSpecifier mailbox,
                         StatusDataType[] data_items,
                         GLib.Cancellable? should_send) {
        base(NAME, null, should_send);

        this.args.add(mailbox.to_parameter());

        assert(data_items.length > 0);
        ListParameter data_item_list = new ListParameter();
        foreach (StatusDataType data_item in data_items)
            data_item_list.add(data_item.to_parameter());

        this.args.add(data_item_list);
    }

}
