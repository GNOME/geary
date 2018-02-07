/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.ImapEngine.YahooAccount : Geary.ImapEngine.GenericAccount {

    public static Geary.Endpoint generate_imap_endpoint() {
        return new Geary.Endpoint(
            "imap.mail.yahoo.com",
            Imap.ClientConnection.DEFAULT_PORT_SSL,
            Geary.Endpoint.Flags.SSL,
            Imap.ClientConnection.RECOMMENDED_TIMEOUT_SEC);
    }

    public static Geary.Endpoint generate_smtp_endpoint() {
        return new Geary.Endpoint(
            "smtp.mail.yahoo.com",
            Smtp.ClientConnection.DEFAULT_PORT_SSL,
            Geary.Endpoint.Flags.SSL,
            Smtp.ClientConnection.DEFAULT_TIMEOUT_SEC);
    }

    private static Gee.HashMap<Geary.FolderPath, Geary.SpecialFolderType>? special_map = null;

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
