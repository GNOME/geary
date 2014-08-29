/* Copyright 2013-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.ImapEngine.OutlookAccount : Geary.ImapEngine.GenericAccount {
    public static Geary.Endpoint generate_imap_endpoint() {
        return new Geary.Endpoint(
            "imap-mail.outlook.com",
            Imap.ClientConnection.DEFAULT_PORT_SSL,
            Geary.Endpoint.Flags.SSL | Geary.Endpoint.Flags.GRACEFUL_DISCONNECT,
            Imap.ClientConnection.RECOMMENDED_TIMEOUT_SEC);
    }
    
    public static Geary.Endpoint generate_smtp_endpoint() {
        return new Geary.Endpoint(
            "smtp-mail.outlook.com",
            Smtp.ClientConnection.DEFAULT_PORT_STARTTLS,
            Geary.Endpoint.Flags.STARTTLS | Geary.Endpoint.Flags.GRACEFUL_DISCONNECT,
            Smtp.ClientConnection.DEFAULT_TIMEOUT_SEC);
    }
    
    public OutlookAccount(string name, AccountInformation account_information, Imap.Account remote,
        ImapDB.Account local) {
        base (name, account_information, false, remote, local);
    }
    
    protected override MinimalFolder new_folder(Geary.FolderPath path, Imap.Account remote_account,
        ImapDB.Account local_account, ImapDB.Folder local_folder) {
        // use the Folder's attributes to determine if it's a special folder type, unless it's
        // INBOX; that's determined by name
        SpecialFolderType special_folder_type;
        if (Imap.MailboxSpecifier.folder_path_is_inbox(path))
            special_folder_type = SpecialFolderType.INBOX;
        else
            special_folder_type = local_folder.get_properties().attrs.get_special_folder_type();
        
        if (special_folder_type == Geary.SpecialFolderType.DRAFTS)
            return new OutlookDraftsFolder(this, remote_account, local_account, local_folder, special_folder_type);
        
        return new OutlookFolder(this, remote_account, local_account, local_folder, special_folder_type);
    }
}

