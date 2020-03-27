/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

private class Geary.ImapEngine.GmailAccount : Geary.ImapEngine.GenericAccount {

    // Archive is handled specially, so don't require it
    private const Geary.SpecialFolderType[] SUPPORTED_SPECIAL_FOLDERS = {
        Geary.SpecialFolderType.DRAFTS,
        Geary.SpecialFolderType.SENT,
        Geary.SpecialFolderType.JUNK,
        Geary.SpecialFolderType.TRASH,
    };


    public static void setup_account(AccountInformation account) {
        account.save_sent = false;
    }

    public static void setup_service(ServiceInformation service) {
        switch (service.protocol) {
        case Protocol.IMAP:
            service.host = "imap.gmail.com";
            service.port = Imap.IMAP_TLS_PORT;
            service.transport_security = TlsNegotiationMethod.TRANSPORT;
            break;

        case Protocol.SMTP:
            service.host = "smtp.gmail.com";
            service.port = Smtp.SUBMISSION_TLS_PORT;
            service.transport_security = TlsNegotiationMethod.TRANSPORT;
            break;
        }
    }


    public GmailAccount(Geary.AccountInformation config,
                        ImapDB.Account local,
                        Endpoint incoming_remote,
                        Endpoint outgoing_remote) {
        base(config, local, incoming_remote, outgoing_remote);
    }

    protected override Geary.SpecialFolderType[] get_supported_special_folders() {
        return SUPPORTED_SPECIAL_FOLDERS;
    }

    protected override MinimalFolder new_folder(ImapDB.Folder local_folder) {
        FolderPath path = local_folder.get_path();
        SpecialFolderType type;
        if (Imap.MailboxSpecifier.folder_path_is_inbox(path)) {
            type = SpecialFolderType.INBOX;
        } else {
            type = local_folder.get_properties().attrs.get_special_folder_type();
            // There can be only one Inbox
            if (type == SpecialFolderType.INBOX) {
                type = SpecialFolderType.NONE;
            }
        }

        switch (type) {
            case SpecialFolderType.ALL_MAIL:
                return new GmailAllMailFolder(this, local_folder, type);

            case SpecialFolderType.DRAFTS:
                return new GmailDraftsFolder(this, local_folder, type);

            case SpecialFolderType.JUNK:
            case SpecialFolderType.TRASH:
                return new GmailSpamTrashFolder(this, local_folder, type);

            default:
                return new GmailFolder(this, local_folder, type);
        }
    }

}
