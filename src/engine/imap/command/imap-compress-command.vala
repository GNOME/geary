/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * See [[http://tools.ietf.org/html/rfc4978]]
 */

public class Geary.Imap.CompressCommand : Command {

    public const string NAME = "compress";

    public const string ALGORITHM_DEFLATE = "deflate";


    public CompressCommand(string algorithm, GLib.Cancellable? should_send) {
        base(NAME, { algorithm }, should_send);
    }

}
