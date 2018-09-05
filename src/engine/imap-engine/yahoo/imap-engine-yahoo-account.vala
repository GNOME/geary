/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.ImapEngine.YahooAccount : Geary.ImapEngine.GenericAccount {


    private static Gee.HashMap<Geary.FolderPath, Geary.SpecialFolderType>? special_map = null;


    public static void setup_service(ServiceInformation service) {
        switch (service.protocol) {
        case Protocol.IMAP:
            service.host = "imap.mail.yahoo.com";
            service.port = Imap.ClientConnection.IMAP_TLS_PORT;
            service.use_ssl = true;
            break;

        case Protocol.SMTP:
            service.host = "smtp.mail.yahoo.com";
            service.port = Smtp.ClientConnection.SUBMISSION_TLS_PORT;
            service.use_ssl = true;
            break;
        }
    }


    public YahooAccount(string name,
                        AccountInformation account_information,
                        ImapDB.Account local) {
        base(name, account_information, local);

        if (special_map == null) {
            special_map = new Gee.HashMap<Geary.FolderPath, Geary.SpecialFolderType>();

            special_map.set(Imap.MailboxSpecifier.inbox.to_folder_path(null, null), Geary.SpecialFolderType.INBOX);
            special_map.set(new Imap.FolderRoot("Sent"), Geary.SpecialFolderType.SENT);
            special_map.set(new Imap.FolderRoot("Draft"), Geary.SpecialFolderType.DRAFTS);
            special_map.set(new Imap.FolderRoot("Bulk Mail"), Geary.SpecialFolderType.SPAM);
            special_map.set(new Imap.FolderRoot("Trash"), Geary.SpecialFolderType.TRASH);
        }
    }

    protected override MinimalFolder new_folder(ImapDB.Folder local_folder) {
        Geary.FolderPath path = local_folder.get_path();
        SpecialFolderType special_folder_type = special_map.has_key(path) ? special_map.get(path)
            : Geary.SpecialFolderType.NONE;
        return new YahooFolder(this, local_folder, special_folder_type);
    }
}
