/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * The IMAP LIST and proprietary XLIST commands.
 *
 * See [[http://tools.ietf.org/html/rfc3501#section-6.3.8]]
 *
 * Some implementations may return the mailbox name itself when using wildcarding.  For example:
 * LIST "" "Parent/%"
 * may return "Parent/Child" on most systems, but some will return "Parent" as well.  Callers
 * should be aware of this when processing, especially if performing a recursive decent.
 *
 * @see MailboxInformation
 */
public class Geary.Imap.ListCommand : Command {


    public const string NAME = "LIST";
    public const string XLIST_NAME = "xlist";


    /**
     * LIST a particular mailbox by {@link MailboxSpecifier}.
     *
     * MailboxSpecifier may contain a wildcard ("%" or "*"), but since the reference field of the
     * LIST command will be empty, it will be listing from the root.
     *
     * Note that IceWarp has an issue where it returns a different MailboxSpecifier for the Spam
     * folder using this variant.  That is:
     *
     * LIST "" % -> "Spam"
     * LIST "" "Spam" -> "~spam"
     *
     * See [[http://redmine.yorba.org/issues/7624]] for more information.
     */
    public ListCommand(MailboxSpecifier mailbox,
                       bool use_xlist,
                       ListReturnParameter? return_param,
                       GLib.Cancellable? should_send) {
        base(use_xlist ? XLIST_NAME : NAME, { "" }, should_send);

        this.args.add(mailbox.to_parameter());
        add_return_parameter(return_param);
    }

    public ListCommand.wildcarded(string reference,
                                  MailboxSpecifier mailbox,
                                  bool use_xlist,
                                  ListReturnParameter? return_param,
                                  GLib.Cancellable? should_send) {
        base(use_xlist ? XLIST_NAME : NAME, { reference }, should_send);

        this.args.add(mailbox.to_parameter());
        add_return_parameter(return_param);
    }

    private void add_return_parameter(ListReturnParameter? return_param) {
        if (return_param == null || return_param.size == 0)
            return;

        this.args.add(StringParameter.get_best_for_unchecked("return"));
        this.args.add(return_param);
    }

}
