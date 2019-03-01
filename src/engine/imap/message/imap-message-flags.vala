/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A collection of {@link MessageFlag}s.
 *
 * @see StoreCommand
 * @see FetchCommand
 * @see FetchedData
 */

public class Geary.Imap.MessageFlags : Geary.Imap.Flags {
    public MessageFlags(Gee.Collection<MessageFlag> flags) {
        base (flags);
    }

    /**
     * Create {@link MessageFlags} from a {@link ListParameter} of flag strings.
     */
    public static MessageFlags from_list(ListParameter listp) throws ImapError {
        Gee.Collection<MessageFlag> list = new Gee.ArrayList<MessageFlag>();
        for (int ctr = 0; ctr < listp.size; ctr++)
            list.add(new MessageFlag(listp.get_as_string(ctr).ascii));

        return new MessageFlags(list);
    }

    /**
     * Create {@link MessageFlags} from a flat string of space-delimited flags.
     */
    public static MessageFlags deserialize(string? str) {
        if (String.is_empty(str))
            return new MessageFlags(new Gee.ArrayList<MessageFlag>());

        string[] tokens = str.split(" ");

        Gee.Collection<MessageFlag> flags = new Gee.ArrayList<MessageFlag>();
        foreach (string token in tokens)
            flags.add(new MessageFlag(token));

        return new MessageFlags(flags);
    }

    internal void add(MessageFlag flag) {
        list.add(flag);
    }

    internal void remove(MessageFlag flag) {
        list.remove(flag);
    }
}

