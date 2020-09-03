/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A representation of the IMAP SEARCH command.
 *
 * See [[http://tools.ietf.org/html/rfc3501#section-6.4.4]].
 */
public class Geary.Imap.SearchCommand : Command {

    public const string NAME = "search";
    public const string UID_NAME = "uid search";

    public SearchCommand(SearchCriteria criteria,
                         GLib.Cancellable? should_send) {
        base(NAME, null, should_send);

        // Extend rather than append the criteria, so the top-level
        // criterion appear in the top-level list and not as a child
        // list
        this.args.extend(criteria);
    }

    public SearchCommand.uid(SearchCriteria criteria,
                             GLib.Cancellable? should_send) {
        base(UID_NAME, null, should_send);

        // Extend rather than append the criteria, so the top-level
        // criterion appear in the top-level list and not as a child
        // list
        this.args.extend(criteria);
    }

}
