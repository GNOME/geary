/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

private class Geary.ImapEngine.OutlookAccount : Geary.ImapEngine.GenericAccount {


    public static void setup_account(AccountInformation account) {
        // noop
    }

    public static void setup_service(ServiceInformation service) {
        switch (service.protocol) {
        case Protocol.IMAP:
            service.host = "imap-mail.outlook.com";
            service.port = Imap.IMAP_TLS_PORT;
            service.transport_security = TlsNegotiationMethod.TRANSPORT;
            break;

        case Protocol.SMTP:
            service.host = "smtp-mail.outlook.com";
            service.port = Smtp.SUBMISSION_PORT;
            service.transport_security = TlsNegotiationMethod.START_TLS;
            break;
        }
    }


    public OutlookAccount(AccountInformation config,
                          ImapDB.Account local,
                          Endpoint incoming_remote,
                          Endpoint outgoing_remote) {
        base(config, local, incoming_remote, outgoing_remote);
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

        if (type == Geary.SpecialFolderType.DRAFTS)
            return new OutlookDraftsFolder(this, local_folder, type);

        return new OutlookFolder(this, local_folder, type);
    }

}
