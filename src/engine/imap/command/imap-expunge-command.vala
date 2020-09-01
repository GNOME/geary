/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * See [[http://tools.ietf.org/html/rfc3501#section-6.4.3]] and
 * [[http://tools.ietf.org/html/rfc4315#section-2.1]]
 */
public class Geary.Imap.ExpungeCommand : Command {

    public const string NAME = "expunge";
    public const string UID_NAME = "uid expunge";

    public ExpungeCommand(GLib.Cancellable? should_send) {
        base(NAME, null, should_send);
    }

    public ExpungeCommand.uid(MessageSet message_set,
                              GLib.Cancellable? should_send) {
        base(UID_NAME, null, should_send);
        assert(message_set.is_uid);
        this.args.add(message_set.to_parameter());
    }

}
