/*
 * Copyright 2017 Michael Gratton <mike@vee.net>
 * Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * The IMAP CREATE command.
 *
 * This command also supports the RFC 6154 Special-Use CREATE
 * extension.
 *
 * See [[http://tools.ietf.org/html/rfc3501#section-6.3.3]] and
 * [[https://tools.ietf.org/html/rfc6154#section-3]]
 */
public class Geary.Imap.CreateCommand : Command {

    public const string NAME_ATOM = "create";
    public const string USE_ATOM = "use";

    public MailboxSpecifier mailbox { get; private set; }

    public Geary.Folder.SpecialUse use {
        get; private set; default = NONE;
    }


    private static MailboxAttribute? get_special_folder_type(Geary.Folder.SpecialUse use) {
        switch (use) {
        case ALL_MAIL:
            return MailboxAttribute.SPECIAL_FOLDER_ALL;

        case ARCHIVE:
            return MailboxAttribute.SPECIAL_FOLDER_ARCHIVE;

        case DRAFTS:
            return MailboxAttribute.SPECIAL_FOLDER_DRAFTS;

        case FLAGGED:
            return MailboxAttribute.SPECIAL_FOLDER_FLAGGED;

        case JUNK:
            return MailboxAttribute.SPECIAL_FOLDER_JUNK;

        case SENT:
            return MailboxAttribute.SPECIAL_FOLDER_SENT;

        case TRASH:
            return MailboxAttribute.SPECIAL_FOLDER_TRASH;

        default:
            return null;
        }
    }

    public CreateCommand(MailboxSpecifier mailbox, GLib.Cancellable? should_send) {
        base(NAME_ATOM, null, should_send);
        this.mailbox = mailbox;
        this.args.add(mailbox.to_parameter());
    }

    public CreateCommand.special_use(MailboxSpecifier mailbox,
                                     Geary.Folder.SpecialUse use,
                                     GLib.Cancellable? should_send) {
        this(mailbox, should_send);
        this.use = use;

        MailboxAttribute? attr = get_special_folder_type(use);
        if (attr != null) {
            ListParameter use_types = new ListParameter();
            use_types.add(new AtomParameter(attr.to_string()));

            ListParameter use_param = new ListParameter();
            use_param.add(new AtomParameter(USE_ATOM));
            use_param.add(use_types);

            this.args.add(use_param);
        }
    }

}
