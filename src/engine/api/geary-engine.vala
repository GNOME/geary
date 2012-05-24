/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Engine {
    public const string SETTINGS_FILENAME = "geary.ini";
    
    private static bool gmime_inited = false;
    private static File? user_data_dir = null;
    private static File? resource_dir = null;
    
    public static void init(File _user_data_dir, File _resource_dir) {
        user_data_dir = _user_data_dir;
        resource_dir = _resource_dir;
        
        // Initialize GMime
        if (!gmime_inited) {
            GMime.init(0);
            gmime_inited = true;
        }
    }
    
    public static Geary.EngineAccount create(Geary.Credentials cred,
        Geary.AccountInformation account_info) throws Error {
        
        account_info.file = get_settings_file(cred);
        return get_account(cred, account_info);
    }
    
    public static Geary.EngineAccount open(Geary.Credentials cred) throws Error {
        return get_account(cred, new AccountInformation.from_file(get_settings_file(cred)));
    }
    
    private static Geary.EngineAccount get_account(Geary.Credentials cred,
        Geary.AccountInformation account_info) throws Error {
        
        switch (account_info.service_provider) {
            case ServiceProvider.GMAIL:
                return new GmailAccount(
                    "Gmail account %s".printf(cred.to_string()), cred.user, account_info, user_data_dir,
                    new Geary.Imap.Account(GmailAccount.IMAP_ENDPOINT, GmailAccount.SMTP_ENDPOINT, cred,
                    account_info), new Geary.Sqlite.Account(cred, user_data_dir, resource_dir));
            
            case ServiceProvider.YAHOO:
                return new YahooAccount(
                    "Yahoo account %s".printf(cred.to_string()), cred.user, account_info, user_data_dir,
                    new Geary.Imap.Account(YahooAccount.IMAP_ENDPOINT, YahooAccount.SMTP_ENDPOINT, cred,
                    account_info), new Geary.Sqlite.Account(cred, user_data_dir, resource_dir));
            
            case ServiceProvider.OTHER:
                Endpoint.Flags imap_flags = account_info.imap_server_ssl ? Endpoint.Flags.SSL
                    : Endpoint.Flags.NONE;
                imap_flags |= Endpoint.Flags.GRACEFUL_DISCONNECT;
                
                Endpoint.Flags smtp_flags = account_info.smtp_server_ssl ? Endpoint.Flags.SSL
                    : Endpoint.Flags.NONE;
                smtp_flags |= Geary.Endpoint.Flags.GRACEFUL_DISCONNECT;
                
                Endpoint imap_endpoint = new Endpoint(account_info.imap_server_host,
                    account_info.imap_server_port, imap_flags, Imap.ClientConnection.DEFAULT_TIMEOUT_SEC);
                    
                Endpoint smtp_endpoint = new Endpoint(account_info.smtp_server_host,
                    account_info.smtp_server_port, smtp_flags, Smtp.ClientConnection.DEFAULT_TIMEOUT_SEC);
                
                return new OtherAccount(
                    "Other account %s".printf(cred.to_string()), cred.user, account_info, user_data_dir,
                    new Geary.Imap.Account(imap_endpoint, smtp_endpoint, cred, account_info),
                    new Geary.Sqlite.Account(cred, user_data_dir, resource_dir));
                
            default:
                assert_not_reached();
        }
    }
    
    private static File get_settings_file(Geary.Credentials cred) {
        return user_data_dir.get_child(cred.user).get_child(SETTINGS_FILENAME);
    }
    
    // Returns a list of usernames associated with Geary.
    public static Gee.List<string> get_usernames() throws Error {
        Gee.ArrayList<string> list = new Gee.ArrayList<string>();
        
        FileEnumerator enumerator = user_data_dir.enumerate_children("standard::*", 
            FileQueryInfoFlags.NONE);
        
        FileInfo? info = null;
        while ((info = enumerator.next_file()) != null) {
            if (info.get_file_type() == FileType.DIRECTORY)
                list.add(info.get_name());
        }
        
        return list;
    }
}
