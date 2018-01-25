/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.ImapEngine.GmailAccount : Geary.ImapEngine.GenericAccount {

    // Archive is handled specially, so don't require it
    private const Geary.SpecialFolderType[] SUPPORTED_SPECIAL_FOLDERS = {
        Geary.SpecialFolderType.DRAFTS,
        Geary.SpecialFolderType.SENT,
        Geary.SpecialFolderType.SPAM,
        Geary.SpecialFolderType.TRASH,
    };

    public static Geary.Endpoint generate_imap_endpoint() {
        return new Geary.Endpoint(
            "imap.gmail.com",
            Imap.ClientConnection.DEFAULT_PORT_SSL,
            Geary.Endpoint.Flags.SSL,
            Imap.ClientConnection.RECOMMENDED_TIMEOUT_SEC);
    }

    public static Geary.Endpoint generate_smtp_endpoint() {
        return new Geary.Endpoint(
            "smtp.gmail.com",
            Smtp.ClientConnection.DEFAULT_PORT_SSL,
            Geary.Endpoint.Flags.SSL,
            Smtp.ClientConnection.DEFAULT_TIMEOUT_SEC);
    }

    public GmailAccount(string name,
                        Geary.AccountInformation account_information,
                        ImapDB.Account local) {
        base(name, account_information, local);
    }

    protected override Geary.SpecialFolderType[] get_supported_special_folders() {
        return SUPPORTED_SPECIAL_FOLDERS;
    }

    protected override MinimalFolder new_folder(ImapDB.Folder local_folder) {
        Geary.FolderPath path = local_folder.get_path();
        SpecialFolderType special_folder_type;
        if (Imap.MailboxSpecifier.folder_path_is_inbox(path))
            special_folder_type = SpecialFolderType.INBOX;
        else
            special_folder_type = local_folder.get_properties().attrs.get_special_folder_type();

        switch (special_folder_type) {
            case SpecialFolderType.ALL_MAIL:
                return new GmailAllMailFolder(this, local_folder, special_folder_type);

            case SpecialFolderType.DRAFTS:
                return new GmailDraftsFolder(this, local_folder, special_folder_type);

            case SpecialFolderType.SPAM:
            case SpecialFolderType.TRASH:
                return new GmailSpamTrashFolder(this, local_folder, special_folder_type);

            default:
                return new GmailFolder(this, local_folder, special_folder_type);
        }
    }

    protected override SearchFolder new_search_folder() {
        return new GmailSearchFolder(this);
    }
}
