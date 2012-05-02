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
                Imap.ClientConnection.DEFAULT_PORT_TLS,
                Geary.Endpoint.Flags.TLS | Geary.Endpoint.Flags.GRACEFUL_DISCONNECT,
                Imap.ClientConnection.DEFAULT_TIMEOUT_SEC);
        }
        
        return _imap_endpoint;
    } }
    
    private static Geary.Endpoint? _smtp_endpoint = null;
    public static Geary.Endpoint SMTP_ENDPOINT { get {
        if (_smtp_endpoint == null) {
            _smtp_endpoint = new Geary.Endpoint(
                "smtp.mail.yahoo.com",
                Smtp.ClientConnection.SECURE_SMTP_PORT,
                Geary.Endpoint.Flags.TLS | Geary.Endpoint.Flags.GRACEFUL_DISCONNECT,
                Smtp.ClientConnection.DEFAULT_TIMEOUT_SEC);
        }
        
        return _smtp_endpoint;
    } }
    
    private static SpecialFolderMap? special_folder_map = null;
    private static Gee.Set<Geary.FolderPath>? ignored_paths = null;
    
    public YahooAccount(string name, string username, AccountInformation account_info,
        File user_data_dir, Imap.Account remote, Sqlite.Account local) {
        base (name, username, account_info, user_data_dir, remote, local);
        
        if (special_folder_map == null || ignored_paths == null)
            initialize_personality();
    }
    
    private static void initialize_personality() {
        special_folder_map = new SpecialFolderMap();
        
        FolderRoot inbox_folder = new FolderRoot(Imap.Account.INBOX_NAME, 
            Imap.Account.ASSUMED_SEPARATOR, false);
        FolderRoot sent_folder = new Geary.FolderRoot("Sent", Imap.Account.ASSUMED_SEPARATOR, false);
        FolderRoot drafts_folder = new Geary.FolderRoot("Draft", Imap.Account.ASSUMED_SEPARATOR,
            false);
        FolderRoot spam_folder = new Geary.FolderRoot("Bulk Mail", Imap.Account.ASSUMED_SEPARATOR,
            false);
        FolderRoot trash_folder = new Geary.FolderRoot("Trash", Imap.Account.ASSUMED_SEPARATOR, false);
        
        special_folder_map.set_folder(new SpecialFolder(Geary.SpecialFolderType.INBOX, _("Inbox"),
            inbox_folder, 0));
        special_folder_map.set_folder(new SpecialFolder(Geary.SpecialFolderType.DRAFTS, _("Drafts"),
            drafts_folder, 1));
        special_folder_map.set_folder(new SpecialFolder(Geary.SpecialFolderType.SENT, _("Sent Mail"),
            sent_folder, 2));
        special_folder_map.set_folder(new SpecialFolder(Geary.SpecialFolderType.SPAM, _("Spam"),
            spam_folder, 3));
        special_folder_map.set_folder(new SpecialFolder(Geary.SpecialFolderType.TRASH, _("Trash"),
            trash_folder, 4));
        
        ignored_paths = new Gee.HashSet<Geary.FolderPath>(Hashable.hash_func, Equalable.equal_func);
        ignored_paths.add(inbox_folder);
        ignored_paths.add(drafts_folder);
        ignored_paths.add(sent_folder);
        ignored_paths.add(spam_folder);
        ignored_paths.add(trash_folder);
    }
    
    public override string get_user_folders_label() {
        return _("Folders");
    }
    
    public override Geary.SpecialFolderMap? get_special_folder_map() {
        return special_folder_map;
    }
    
    public override Gee.Set<Geary.FolderPath>? get_ignored_paths() {
        return ignored_paths;
    }
    
    public override bool delete_is_archive() {
        return false;
    }
}

