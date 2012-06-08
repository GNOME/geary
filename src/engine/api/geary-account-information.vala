/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.AccountInformation : Object {
    private const string GROUP = "AccountInformation";
    private const string REAL_NAME_KEY = "real_name";
    private const string SERVICE_PROVIDER_KEY = "service_provider";
    private const string REMEMBER_PASSWORD_KEY = "remember_password";
    private const string IMAP_HOST = "imap_host";
    private const string IMAP_PORT = "imap_port";
    private const string IMAP_SSL = "imap_ssl";
    private const string IMAP_PIPELINE = "imap_pipeline";
    private const string SMTP_HOST = "smtp_host";
    private const string SMTP_PORT = "smtp_port";
    private const string SMTP_SSL = "smtp_ssl";
    
    public const string SETTINGS_FILENAME = "geary.ini";
    
    internal File? settings_dir;
    internal File? file = null;
    public string real_name { get; set; }
    public Geary.ServiceProvider service_provider { get; set; }
    
    public string imap_server_host { get; set; default = ""; }
    public uint16 imap_server_port { get; set; default = Imap.ClientConnection.DEFAULT_PORT_SSL; }
    public bool imap_server_ssl { get; set; default = true; }
    public bool imap_server_pipeline { get; set; default = true; }
    
    public string smtp_server_host { get; set; default = ""; }
    public uint16 smtp_server_port { get; set; default = Smtp.ClientConnection.DEFAULT_PORT_SSL; }
    public bool smtp_server_ssl { get; set; default = true; }
    
    public Geary.Credentials credentials { get; private set; }
    public bool remember_password { get; set; default = true; }
    
    public AccountInformation(Geary.Credentials credentials) {
        this.credentials = credentials;
        
        this.settings_dir = Geary.Engine.user_data_dir.get_child(credentials.user);
        this.file = settings_dir.get_child(SETTINGS_FILENAME);
    }
    
    public void load_info_from_file() throws Error {
        KeyFile key_file = new KeyFile();
        try {
            key_file.load_from_file(file.get_path() ?? "", KeyFileFlags.NONE);
        } catch (FileError.NOENT err) {
            // The file didn't exist.  No big deal -- just means we give you the defaults.
        } finally {
            real_name = get_string_value(key_file, GROUP, REAL_NAME_KEY);
            remember_password = get_bool_value(key_file, GROUP, REMEMBER_PASSWORD_KEY, true);
            service_provider = Geary.ServiceProvider.from_string(get_string_value(key_file, GROUP,
                SERVICE_PROVIDER_KEY));
            
            imap_server_host = get_string_value(key_file, GROUP, IMAP_HOST);
            imap_server_port = get_uint16_value(key_file, GROUP, IMAP_PORT,
                Imap.ClientConnection.DEFAULT_PORT_SSL);
            imap_server_ssl = get_bool_value(key_file, GROUP, IMAP_SSL, true);
            imap_server_pipeline = get_bool_value(key_file, GROUP, IMAP_PIPELINE, true);
            
            smtp_server_host = get_string_value(key_file, GROUP, SMTP_HOST);
            smtp_server_port = get_uint16_value(key_file, GROUP, SMTP_PORT,
                Geary.Smtp.ClientConnection.DEFAULT_PORT_SSL);
            smtp_server_ssl = get_bool_value(key_file, GROUP, SMTP_SSL, true);
        }
    }
    
    public async bool validate_async(Cancellable? cancellable = null) throws IOError {
        Geary.Endpoint endpoint;
        switch (service_provider) {
            case ServiceProvider.GMAIL:
                endpoint = GmailAccount.IMAP_ENDPOINT;
            break;
            
            case ServiceProvider.YAHOO:
                endpoint = YahooAccount.IMAP_ENDPOINT;
            break;
            
            case ServiceProvider.OTHER:
                Endpoint.Flags imap_flags = imap_server_ssl ? Endpoint.Flags.SSL : Endpoint.Flags.NONE;
                imap_flags |= Endpoint.Flags.GRACEFUL_DISCONNECT;
                
                endpoint = new Endpoint(imap_server_host, imap_server_port, imap_flags,
                    Imap.ClientConnection.RECOMMENDED_TIMEOUT_SEC);
            break;
            
            default:
                assert_not_reached();
        }
        
        Geary.Imap.ClientSessionManager client_session_manager =
            new Geary.Imap.ClientSessionManager(endpoint, credentials, this, 0);
        Geary.Imap.ClientSession? client_session = null;
        try {
            client_session = yield client_session_manager.get_authorized_session_async(cancellable);
        } catch (Error err) {
            debug("Error validating account info: %s", err.message);
        }
        
        if (client_session != null) {
            string current_mailbox;
            Geary.Imap.ClientSession.Context context = client_session.get_context(out current_mailbox);
            return context == Geary.Imap.ClientSession.Context.AUTHORIZED;
        }
        
        return false;
    }
    
    public Geary.EngineAccount get_account() throws EngineError {
        Geary.Sqlite.Account sqlite_account =
            new Geary.Sqlite.Account(credentials.user);
            
        switch (service_provider) {
            case ServiceProvider.GMAIL:
                return new GmailAccount("Gmail account %s".printf(credentials.to_string()),
                    credentials.user, this, Engine.user_data_dir, new Geary.Imap.Account(
                    GmailAccount.IMAP_ENDPOINT, GmailAccount.SMTP_ENDPOINT, credentials, this),
                    sqlite_account);
            
            case ServiceProvider.YAHOO:
                return new YahooAccount("Yahoo account %s".printf(credentials.to_string()),
                    credentials.user, this, Engine.user_data_dir, new Geary.Imap.Account(
                    YahooAccount.IMAP_ENDPOINT, YahooAccount.SMTP_ENDPOINT, credentials, this),
                    sqlite_account);
            
            case ServiceProvider.OTHER:
                Endpoint.Flags imap_flags = imap_server_ssl ? Endpoint.Flags.SSL : Endpoint.Flags.NONE;
                imap_flags |= Endpoint.Flags.GRACEFUL_DISCONNECT;
                
                Endpoint.Flags smtp_flags = smtp_server_ssl ? Endpoint.Flags.SSL : Endpoint.Flags.NONE;
                smtp_flags |= Geary.Endpoint.Flags.GRACEFUL_DISCONNECT;
                
                Endpoint imap_endpoint = new Endpoint(imap_server_host, imap_server_port,
                    imap_flags, Imap.ClientConnection.RECOMMENDED_TIMEOUT_SEC);
                    
                Endpoint smtp_endpoint = new Endpoint(smtp_server_host, smtp_server_port,
                    smtp_flags, Smtp.ClientConnection.DEFAULT_TIMEOUT_SEC);
                
                return new OtherAccount("Other account %s".printf(credentials.to_string()),
                    credentials.user, this, Engine.user_data_dir, new Geary.Imap.Account(imap_endpoint,
                    smtp_endpoint, credentials, this), sqlite_account);
                
            default:
                throw new EngineError.NOT_FOUND("Service provider of type %s not known",
                    service_provider.to_string());
        }
    }
    
    private string get_string_value(KeyFile key_file, string group, string key, string _default = "") {
        string v = _default;
        try {
            v = key_file.get_value(group, key);
        } catch(KeyFileError err) {
            // Ignore.
        }
        return v;
    }
    
    private bool get_bool_value(KeyFile key_file, string group, string key, bool _default = false) {
        bool v = _default;
        try {
            v = key_file.get_boolean(group, key);
        } catch(KeyFileError err) {
            // Ignore.
        }
        return v;
    }
    
    private uint16 get_uint16_value(KeyFile key_file, string group, string key, uint16 _default = 0) {
        uint16 v = _default;
        try {
            v = (uint16) key_file.get_integer(group, key);
        } catch(KeyFileError err) {
            // Ignore.
        }
        return v;
    }
    
    public async void store_async(Cancellable? cancellable = null) {
        assert(file != null);
        
        if (!settings_dir.query_exists(cancellable)) {
            try {
                settings_dir.make_directory_with_parents();
            } catch (Error err) {
                error("Error creating settings directory for user '%s': %s", credentials.user,
                    err.message);
            }
        }
        
        if (!file.query_exists(cancellable)) {
            try {
                yield file.create_async(FileCreateFlags.REPLACE_DESTINATION);
            } catch (Error err) {
                debug("Error creating account info file: %s", err.message);
            }
        }
        
        KeyFile key_file = new KeyFile();
        
        key_file.set_value(GROUP, REAL_NAME_KEY, real_name);
        key_file.set_value(GROUP, SERVICE_PROVIDER_KEY, service_provider.to_string());
        key_file.set_boolean(GROUP, REMEMBER_PASSWORD_KEY, remember_password);
        
        key_file.set_value(GROUP, IMAP_HOST, imap_server_host);
        key_file.set_integer(GROUP, IMAP_PORT, imap_server_port);
        key_file.set_boolean(GROUP, IMAP_SSL, imap_server_ssl);
        key_file.set_boolean(GROUP, IMAP_PIPELINE, imap_server_pipeline);
        
        key_file.set_value(GROUP, SMTP_HOST, smtp_server_host);
        key_file.set_integer(GROUP, SMTP_PORT, smtp_server_port);
        key_file.set_boolean(GROUP, SMTP_SSL, smtp_server_ssl);
        
        string data = key_file.to_data();
        string new_etag;
        
        try {
            yield file.replace_contents_async(data.data, null, false, FileCreateFlags.NONE,
                cancellable, out new_etag);
        } catch (Error err) {
            debug("Error writing to account info file: %s", err.message);
        }
    }
}
