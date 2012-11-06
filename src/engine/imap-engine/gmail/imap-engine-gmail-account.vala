/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

private class Geary.ImapEngine.GmailAccount : Geary.ImapEngine.GenericAccount {
    private const string GMAIL_FOLDER = "[Gmail]";
    private const string GOOGLEMAIL_FOLDER = "[Google Mail]";
    
    private static Geary.Endpoint? _imap_endpoint = null;
    public static Geary.Endpoint IMAP_ENDPOINT { get {
        if (_imap_endpoint == null) {
            _imap_endpoint = new Geary.Endpoint(
                "imap.gmail.com",
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
                "smtp.gmail.com",
                Smtp.ClientConnection.DEFAULT_PORT_SSL,
                Geary.Endpoint.Flags.SSL | Geary.Endpoint.Flags.GRACEFUL_DISCONNECT,
                Smtp.ClientConnection.DEFAULT_TIMEOUT_SEC);
        }
        
        return _smtp_endpoint;
    } }
    
    private static Gee.HashMap<Geary.FolderPath, Geary.SpecialFolderType>? path_type_map = null;
    
    public GmailAccount(string name, Geary.AccountSettings settings, Imap.Account remote,
        ImapDB.Account local) {
        base (name, settings, remote, local);
        
        if (path_type_map == null) {
            path_type_map = new Gee.HashMap<Geary.FolderPath, Geary.SpecialFolderType>(
                Hashable.hash_func, Equalable.equal_func);
            
            path_type_map.set(new Geary.FolderRoot(Imap.Account.INBOX_NAME, Imap.Account.ASSUMED_SEPARATOR,
                Imap.Folder.CASE_SENSITIVE), SpecialFolderType.INBOX);
            
            Geary.FolderPath gmail_root = new Geary.FolderRoot(GMAIL_FOLDER,
                Imap.Account.ASSUMED_SEPARATOR, Imap.Folder.CASE_SENSITIVE);
            Geary.FolderPath googlemail_root = new Geary.FolderRoot(GOOGLEMAIL_FOLDER,
                Imap.Account.ASSUMED_SEPARATOR, Imap.Folder.CASE_SENSITIVE);
            
            path_type_map.set(gmail_root.get_child("Drafts"), SpecialFolderType.DRAFTS);
            path_type_map.set(googlemail_root.get_child("Drafts"), SpecialFolderType.DRAFTS);
            
            path_type_map.set(gmail_root.get_child("Sent Mail"), SpecialFolderType.SENT);
            path_type_map.set(googlemail_root.get_child("Sent Mail"), SpecialFolderType.SENT);
            
            path_type_map.set(gmail_root.get_child("Starred"), SpecialFolderType.FLAGGED);
            path_type_map.set(googlemail_root.get_child("Starred"), SpecialFolderType.FLAGGED);
            
            path_type_map.set(gmail_root.get_child("Important"), SpecialFolderType.IMPORTANT);
            path_type_map.set(googlemail_root.get_child("Important"), SpecialFolderType.IMPORTANT);
            
            path_type_map.set(gmail_root.get_child("All Mail"), SpecialFolderType.ALL_MAIL);
            path_type_map.set(googlemail_root.get_child("All Mail"), SpecialFolderType.ALL_MAIL);
            
            path_type_map.set(gmail_root.get_child("Spam"), SpecialFolderType.SPAM);
            path_type_map.set(googlemail_root.get_child("Spam"), SpecialFolderType.SPAM);
            
            path_type_map.set(gmail_root.get_child("Trash"), SpecialFolderType.TRASH);
            path_type_map.set(googlemail_root.get_child("Trash"), SpecialFolderType.TRASH);
        }
    }
    
    protected override GenericFolder new_folder(Geary.FolderPath path, Imap.Account remote_account,
        ImapDB.Account local_account, ImapDB.Folder local_folder) {
        // although Gmail supports XLIST, this will be called on startup if the XLIST properties
        // for the folders hasn't been retrieved yet.  Once they've been retrieved and stored in
        // the local database, this won't be called again
        SpecialFolderType special_folder_type = path_type_map.has_key(path) ? path_type_map.get(path)
            : SpecialFolderType.NONE;
        
        switch (special_folder_type) {
            case SpecialFolderType.ALL_MAIL:
                return new GenericAllMailFolder(this, remote_account, local_account, local_folder,
                    special_folder_type);
            
            case SpecialFolderType.SENT:
                return new GenericSentMailFolder(this, remote_account, local_account, local_folder,
                    special_folder_type);
            
            case SpecialFolderType.TRASH:
                return new GenericTrashFolder(this, remote_account, local_account, local_folder,
                    special_folder_type);
            
            default:
                return new GmailFolder(this, remote_account, local_account, local_folder, special_folder_type);
        }
    }
}

