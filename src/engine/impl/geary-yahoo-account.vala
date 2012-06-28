/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

private class Geary.YahooAccount : Geary.GenericImapAccount {
    private static Geary.Endpoint? _imap_endpoint = null;
    public static Geary.Endpoint IMAP_ENDPOINT { get {
        if (_imap_endpoint == null) {
            _imap_endpoint = new Geary.Endpoint(
                "imap.mail.yahoo.com",
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
                "smtp.mail.yahoo.com",
                Smtp.ClientConnection.DEFAULT_PORT_SSL,
                Geary.Endpoint.Flags.SSL | Geary.Endpoint.Flags.GRACEFUL_DISCONNECT,
                Smtp.ClientConnection.DEFAULT_TIMEOUT_SEC);
        }
        
        return _smtp_endpoint;
    } }
    
    private static Gee.HashMap<Geary.FolderPath, Geary.SpecialFolderType>? special_map = null;
    
    public YahooAccount(string name, string username, AccountInformation account_info,
        File user_data_dir, Imap.Account remote, Sqlite.Account local) {
        base (name, username, account_info, user_data_dir, remote, local);
        
        if (special_map == null) {
            special_map = new Gee.HashMap<Geary.FolderPath, Geary.SpecialFolderType>(
                Hashable.hash_func, Equalable.equal_func);
            
            special_map.set(new Geary.FolderRoot(Imap.Account.INBOX_NAME, Imap.Account.ASSUMED_SEPARATOR, false),
                Geary.SpecialFolderType.INBOX);
            special_map.set(new Geary.FolderRoot("Sent", Imap.Account.ASSUMED_SEPARATOR, false),
                Geary.SpecialFolderType.SENT);
            special_map.set(new Geary.FolderRoot("Draft", Imap.Account.ASSUMED_SEPARATOR, false),
                Geary.SpecialFolderType.DRAFTS);
            special_map.set(new Geary.FolderRoot("Bulk Mail", Imap.Account.ASSUMED_SEPARATOR, false),
                Geary.SpecialFolderType.SPAM);
            special_map.set(new Geary.FolderRoot("Trash", Imap.Account.ASSUMED_SEPARATOR, false),
                Geary.SpecialFolderType.TRASH);
        }
    }
    
    protected override GenericImapFolder new_folder(Geary.FolderPath path, Imap.Account remote_account,
        Sqlite.Account local_account, Sqlite.Folder local_folder) {
        return new YahooFolder(this, remote_account, local_account, local_folder,
            special_map.has_key(path) ? special_map.get(path) : Geary.SpecialFolderType.NONE);
    }
}

