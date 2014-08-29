/* Copyright 2011-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.ImapEngine.GmailAccount : Geary.ImapEngine.GenericAccount {
    public static Geary.Endpoint generate_imap_endpoint() {
        return new Geary.Endpoint(
            "imap.gmail.com",
            Imap.ClientConnection.DEFAULT_PORT_SSL,
            Geary.Endpoint.Flags.SSL | Geary.Endpoint.Flags.GRACEFUL_DISCONNECT,
            Imap.ClientConnection.RECOMMENDED_TIMEOUT_SEC);
    }
    
    public static Geary.Endpoint generate_smtp_endpoint() {
        return new Geary.Endpoint(
            "smtp.gmail.com",
            Smtp.ClientConnection.DEFAULT_PORT_SSL,
            Geary.Endpoint.Flags.SSL | Geary.Endpoint.Flags.GRACEFUL_DISCONNECT,
            Smtp.ClientConnection.DEFAULT_TIMEOUT_SEC);
    }
    
    public GmailAccount(string name, Geary.AccountInformation account_information,
        Imap.Account remote, ImapDB.Account local) {
        base (name, account_information, true, remote, local);
    }
    
    protected override MinimalFolder new_folder(Geary.FolderPath path, Imap.Account remote_account,
        ImapDB.Account local_account, ImapDB.Folder local_folder) {
        SpecialFolderType special_folder_type;
        if (Imap.MailboxSpecifier.folder_path_is_inbox(path))
            special_folder_type = SpecialFolderType.INBOX;
        else
            special_folder_type = local_folder.get_properties().attrs.get_special_folder_type();
        
        switch (special_folder_type) {
            case SpecialFolderType.ALL_MAIL:
                return new MinimalFolder(this, remote_account, local_account, local_folder,
                    special_folder_type);
            
            case SpecialFolderType.DRAFTS:
            case SpecialFolderType.SPAM:
            case SpecialFolderType.TRASH:
                return new GenericFolder(this, remote_account, local_account, local_folder,
                    special_folder_type);
            
            default:
                return new GmailFolder(this, remote_account, local_account, local_folder, special_folder_type);
        }
    }
    
    protected override SearchFolder new_search_folder() {
        return new GmailSearchFolder(this);
    }
}

