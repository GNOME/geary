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

    public const string NAME = "create";
    public const string USE = "use";

    public MailboxSpecifier mailbox { get; private set; }

    public Geary.SpecialFolderType use {
        get; private set; default = Geary.SpecialFolderType.NONE;
    }


    private static MailboxAttribute? get_special_folder_type(Geary.SpecialFolderType type) {
        switch (type) {
        case Geary.SpecialFolderType.TRASH:
            return MailboxAttribute.SPECIAL_FOLDER_TRASH;

        case Geary.SpecialFolderType.DRAFTS:
            return MailboxAttribute.SPECIAL_FOLDER_DRAFTS;

        case Geary.SpecialFolderType.SENT:
            return MailboxAttribute.SPECIAL_FOLDER_SENT;

        case Geary.SpecialFolderType.ARCHIVE:
            return MailboxAttribute.SPECIAL_FOLDER_ARCHIVE;

        case Geary.SpecialFolderType.SPAM:
            return MailboxAttribute.SPECIAL_FOLDER_JUNK;

        case Geary.SpecialFolderType.FLAGGED:
            return MailboxAttribute.SPECIAL_FOLDER_STARRED;

        case Geary.SpecialFolderType.ALL_MAIL:
            return MailboxAttribute.SPECIAL_FOLDER_ALL;

        default:
            return null;
        }
    }

    public CreateCommand(MailboxSpecifier mailbox) {
        base(NAME);
        this.mailbox = mailbox;
        add(mailbox.to_parameter());
    }

    public CreateCommand.special_use(MailboxSpecifier mailbox,
                                     Geary.SpecialFolderType use) {
        this(mailbox);
        this.use = use;

        MailboxAttribute? attr = get_special_folder_type(use);
        if (attr != null) {
            ListParameter use_types = new ListParameter();
            use_types.add(new AtomParameter(attr.to_string()));

            ListParameter use_param = new ListParameter();
            use_param.add(new AtomParameter(USE));
            use_param.add(use_types);

            add(use_param);
        }
    }

}
