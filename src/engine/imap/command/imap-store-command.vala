/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * The IMAP `STORE` and `UID STORE` commands.
 *
 * See [[http://tools.ietf.org/html/rfc3501#section-6.4.6]]
 *
 * @see FetchCommand
 * @see FetchedData
 */
public class Geary.Imap.StoreCommand : Command {

    public const string NAME = "STORE";
    public const string UID_NAME = "UID STORE";

    /** Defines how the given flags are used to update message's flags. */
    public enum Mode {

        /** Sets the given flags as the complete set for the message's. */
        SET_FLAGS,

        /** Adds the given flags to the message's existing flags. */
        ADD_FLAGS,

        /** Removes the given flags from the message's existing flags. */
        REMOVE_FLAGS,
    }

    /** Specifies optional functionality for the command. */
    [Flags]
    public enum Options {

        /** No options should be used. */
        NONE,

        /** Prevent the server from sending an untagged FETCH in response. */
        SILENT
    }

    public StoreCommand(MessageSet message_set,
                        Mode mode,
                        Options options,
                        Gee.List<MessageFlag> flag_list,
                        GLib.Cancellable? should_send) {
        base(message_set.is_uid ? UID_NAME : NAME, null, should_send);

        this.args.add(message_set.to_parameter());

        var command = new GLib.StringBuilder();
        switch (mode) {
        case ADD_FLAGS:
            command.append_c('+');
            break;
        case REMOVE_FLAGS:
            command.append_c('-');
            break;
        case SET_FLAGS:
            // noop
            break;
        }
        command.append("FLAGS");
        if (Options.SILENT in options) {
            command.append(".SILENT");
        }
        this.args.add(new AtomParameter(command.str));

        var list = new ListParameter();
        foreach (var flag in flag_list) {
            list.add(new AtomParameter(flag.value));
        }

        this.args.add(list);
    }

}
