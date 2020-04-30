/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

private class Geary.ImapEngine.YahooAccount : Geary.ImapEngine.GenericAccount {


    public static void setup_account(AccountInformation account) {
        // noop
    }

    public static void setup_service(ServiceInformation service) {
        switch (service.protocol) {
        case Protocol.IMAP:
            service.host = "imap.mail.yahoo.com";
            service.port = Imap.IMAP_TLS_PORT;
            service.transport_security = TlsNegotiationMethod.TRANSPORT;
            break;

        case Protocol.SMTP:
            service.host = "smtp.mail.yahoo.com";
            service.port = Smtp.SUBMISSION_TLS_PORT;
            service.transport_security = TlsNegotiationMethod.TRANSPORT;
            break;
        }
    }


    public YahooAccount(AccountInformation config,
                        ImapDB.Account local,
                        Endpoint incoming_remote,
                        Endpoint outgoing_remote) {
        base(config, local, incoming_remote, outgoing_remote);
    }

    protected override MinimalFolder new_folder(ImapDB.Folder local_folder) {
        FolderPath path = local_folder.get_path();
        Folder.SpecialUse use = NONE;
        if (Imap.MailboxSpecifier.folder_path_is_inbox(path)) {
            use = INBOX;
        } else {
            // Despite Yahoo not advertising that it supports
            // SPECIAL-USE via its CAPABILITIES, it lists the
            // appropriate attributes in LIST results anyway, so we
            // can just consult that. :|
            use = local_folder.get_properties().attrs.get_special_use();
            // There can be only one Inbox
            if (use == INBOX) {
                use = NONE;
            }
        }

        return new YahooFolder(this, local_folder, use);
    }

}
