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
    
    private Gee.HashMap<Geary.FolderPath, Geary.SpecialFolderType> special_map = new Gee.HashMap<
        Geary.FolderPath, Geary.SpecialFolderType>(Hashable.hash_func, Equalable.equal_func);
    
    public YahooAccount(string name, string username, AccountInformation account_info,
        File user_data_dir, Imap.Account remote, Sqlite.Account local) {
        base (name, username, account_info, user_data_dir, remote, local);
        
        FolderPath sent = new Geary.FolderRoot("Sent", Imap.Account.ASSUMED_SEPARATOR, false);
        special_map.set(sent, Geary.SpecialFolderType.SENT);
        
        FolderPath drafts = new Geary.FolderRoot("Draft", Imap.Account.ASSUMED_SEPARATOR, false);
        special_map.set(drafts, Geary.SpecialFolderType.DRAFTS);
        
        FolderPath bulk = new Geary.FolderRoot("Bulk Mail", Imap.Account.ASSUMED_SEPARATOR, false);
        special_map.set(bulk, Geary.SpecialFolderType.SPAM);
        
        FolderPath trash = new Geary.FolderRoot("Trash", Imap.Account.ASSUMED_SEPARATOR, false);
        special_map.set(trash, Geary.SpecialFolderType.TRASH);
    }
    
    protected override Geary.SpecialFolderType get_special_folder_type_for_path(Geary.FolderPath path) {
        return special_map.has_key(path) ? special_map.get(path) : Geary.SpecialFolderType.NONE;
    }
    
    public override bool delete_is_archive() {
        return false;
    }
}

