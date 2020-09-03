/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * See [[http://tools.ietf.org/html/rfc3501#section-6.1.3]]
 */

public class Geary.Imap.LogoutCommand : Command {

    public const string NAME = "logout";

    public LogoutCommand(GLib.Cancellable? should_send) {
        base(NAME, null, should_send);
    }

}
