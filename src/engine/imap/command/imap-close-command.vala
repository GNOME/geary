/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * See [[http://tools.ietf.org/html/rfc3501#section-6.4.2]]
 */

public class Geary.Imap.CloseCommand : Command {

    public const string NAME = "close";

    public CloseCommand(GLib.Cancellable? should_send) {
        base(NAME, null, should_send);
    }

}
