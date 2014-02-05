/* Copyright 2013-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.ImapEngine.OutlookAccount : Geary.ImapEngine.GenericAccount {
    private static Geary.Endpoint? _imap_endpoint = null;
    public static Geary.Endpoint IMAP_ENDPOINT { get {
        if (_imap_endpoint == null) {
            _imap_endpoint = new Geary.Endpoint(
                "imap-mail.outlook.com",
                Imap.ClientConnection.DEFAULT_PORT_SSL,
                Geary.Endpoint.Flags.SSL | Geary.Endpoint.Flags.GRACEFUL_DISCONNECT,
                Imap.ClientConnection.RECOMMENDED_TIMEOUT_SEC);
        }
        
        return _imap_endpoint;
    } }
    
    private static Geary.Endpoint? _smtp_endpoint = null;
    public static Geary.Endpoint SMTP_ENDPOINT { get {
        if (_smtp_endpoint == null) {
            _smtp_endpoint = new Geary.Endpoint(
                "smtp-mail.outlook.com",
                Smtp.ClientConnection.DEFAULT_PORT_STARTTLS,
                Geary.Endpoint.Flags.STARTTLS | Geary.Endpoint.Flags.GRACEFUL_DISCONNECT,
                Smtp.ClientConnection.DEFAULT_TIMEOUT_SEC);
        }
        
        return _smtp_endpoint;
    } }
    
    public OutlookAccount(string name, AccountInformation account_information, Imap.Account remote,
        ImapDB.Account local) {
        base (name, account_information, false, remote, local);
    }
    
    protected override GenericFolder new_folder(Geary.FolderPath path, Imap.Account remote_account,
        ImapDB.Account local_account, ImapDB.Folder local_folder) {
        // use the Folder's attributes to determine if it's a special folder type, unless it's
        // INBOX; that's determined by name
        SpecialFolderType special_folder_type;
        if (Imap.MailboxSpecifier.folder_path_is_inbox(path))
            special_folder_type = SpecialFolderType.INBOX;
        else
            special_folder_type = local_folder.get_properties().attrs.get_special_folder_type();
        
        // generate properly-interfaced Folder depending on the special type
        // Proper Drafts support depends on Outlook.com supporting UIDPLUS or us devising another
        // mechanism to associate new messages with drafts-in-progress; see
        // http://redmine.yorba.org/issues/7495
        switch (special_folder_type) {
            case SpecialFolderType.SENT:
                return new GenericSentMailFolder(this, remote_account, local_account, local_folder,
                    special_folder_type);
            
            case SpecialFolderType.TRASH:
                return new GenericTrashFolder(this, remote_account, local_account, local_folder,
                    special_folder_type);
            
            default:
                return new OutlookFolder(this, remote_account, local_account, local_folder,
                    special_folder_type);
        }
    }
}

