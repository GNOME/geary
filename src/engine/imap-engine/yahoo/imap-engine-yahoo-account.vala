/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

private class Geary.ImapEngine.YahooAccount : Geary.ImapEngine.GenericAccount {


    private static Gee.HashMap<Geary.FolderPath, Geary.SpecialFolderType>? special_map = null;


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

        if (special_map == null) {
            special_map = new Gee.HashMap<Geary.FolderPath, Geary.SpecialFolderType>();

            FolderRoot root = this.local.imap_folder_root;
            special_map.set(
                this.local.imap_folder_root.inbox, Geary.SpecialFolderType.INBOX
            );
            special_map.set(
                root.get_child("Sent"), Geary.SpecialFolderType.SENT
            );
            special_map.set(
                root.get_child("Draft"), Geary.SpecialFolderType.DRAFTS
            );
            special_map.set(
                root.get_child("Bulk Mail"), Geary.SpecialFolderType.SPAM
            );
            special_map.set(
                root.get_child("Trash"), Geary.SpecialFolderType.TRASH
            );
        }
    }

    protected override MinimalFolder new_folder(ImapDB.Folder local_folder) {
        Geary.FolderPath path = local_folder.get_path();
        SpecialFolderType special_folder_type = special_map.has_key(path) ? special_map.get(path)
            : Geary.SpecialFolderType.NONE;
        return new YahooFolder(this, local_folder, special_folder_type);
    }
}
