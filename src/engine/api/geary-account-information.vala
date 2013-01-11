/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.AccountInformation : Object {
    private const string GROUP = "AccountInformation";
    private const string REAL_NAME_KEY = "real_name";
    private const string SERVICE_PROVIDER_KEY = "service_provider";
    private const string IMAP_USERNAME_KEY = "imap_username";
    private const string IMAP_REMEMBER_PASSWORD_KEY = "imap_remember_password";
    private const string SMTP_USERNAME_KEY = "smtp_username";
    private const string SMTP_REMEMBER_PASSWORD_KEY = "smtp_remember_password";
    private const string IMAP_HOST = "imap_host";
    private const string IMAP_PORT = "imap_port";
    private const string IMAP_SSL = "imap_ssl";
    private const string IMAP_STARTTLS = "imap_starttls";
    private const string IMAP_PIPELINE = "imap_pipeline";
    private const string SMTP_HOST = "smtp_host";
    private const string SMTP_PORT = "smtp_port";
    private const string SMTP_SSL = "smtp_ssl";
    private const string SMTP_STARTTLS = "smtp_starttls";
    
    public const string SETTINGS_FILENAME = "geary.ini";
    
    internal File settings_dir;
    internal File file;
    
    public string real_name { get; set; }
    public string email { get; set; }
    public Geary.ServiceProvider service_provider { get; set; }
    public bool imap_server_pipeline { get; set; default = true; }

    // These properties are only used if the service provider's account type does not override them.
    public string default_imap_server_host { get; set; }
    public uint16 default_imap_server_port  { get; set; }
    public bool default_imap_server_ssl  { get; set; }
    public bool default_imap_server_starttls  { get; set; }
    public string default_smtp_server_host  { get; set; }
    public uint16 default_smtp_server_port  { get; set; }
    public bool default_smtp_server_ssl  { get; set; }
    public bool default_smtp_server_starttls { get; set; }

    public Geary.Credentials imap_credentials { get; set; default = new Geary.Credentials(null, null); }
    public bool imap_remember_password { get; set; default = true; }
    public Geary.Credentials smtp_credentials { get; set; default = new Geary.Credentials(null, null); }
    public bool smtp_remember_password { get; set; default = true; }
    
    internal AccountInformation(File directory) {
        this.email = directory.get_basename();
        this.settings_dir = directory;
        this.file = settings_dir.get_child(SETTINGS_FILENAME);
        
        KeyFile key_file = new KeyFile();
        try {
            key_file.load_from_file(file.get_path() ?? "", KeyFileFlags.NONE);
        } catch (FileError err) {
            // See comment in next catch block.
        } catch (KeyFileError err) {
            // It's no big deal if we couldn't load the key file -- just means we give you the defaults.
        } finally {
            real_name = get_string_value(key_file, GROUP, REAL_NAME_KEY);
            imap_credentials.user = get_string_value(key_file, GROUP, IMAP_USERNAME_KEY, email);
            imap_remember_password = get_bool_value(key_file, GROUP, IMAP_REMEMBER_PASSWORD_KEY, true);
            smtp_credentials.user = get_string_value(key_file, GROUP, SMTP_USERNAME_KEY, email);
            smtp_remember_password = get_bool_value(key_file, GROUP, SMTP_REMEMBER_PASSWORD_KEY, true);
            service_provider = Geary.ServiceProvider.from_string(get_string_value(key_file, GROUP,
                SERVICE_PROVIDER_KEY, Geary.ServiceProvider.GMAIL.to_string()));
            
            imap_server_pipeline = get_bool_value(key_file, GROUP, IMAP_PIPELINE, true);

            if (service_provider == ServiceProvider.OTHER) {
                default_imap_server_host = get_string_value(key_file, GROUP, IMAP_HOST);
                default_imap_server_port = get_uint16_value(key_file, GROUP, IMAP_PORT,
                    Imap.ClientConnection.DEFAULT_PORT_SSL);
                default_imap_server_ssl = get_bool_value(key_file, GROUP, IMAP_SSL, true);
                default_imap_server_starttls = get_bool_value(key_file, GROUP, IMAP_STARTTLS, false);
                
                default_smtp_server_host = get_string_value(key_file, GROUP, SMTP_HOST);
                default_smtp_server_port = get_uint16_value(key_file, GROUP, SMTP_PORT,
                    Geary.Smtp.ClientConnection.DEFAULT_PORT_SSL);
                default_smtp_server_ssl = get_bool_value(key_file, GROUP, SMTP_SSL, true);
                default_smtp_server_starttls = get_bool_value(key_file, GROUP, SMTP_STARTTLS, false);
            }
        }
        
        // currently IMAP pipelining is *always* turned off with generic servers; see
        // http://redmine.yorba.org/issues/5224
        if (service_provider == Geary.ServiceProvider.OTHER)
            imap_server_pipeline = false;
    }
    
    public async bool validate_async(Cancellable? cancellable = null) throws EngineError {
        AccountSettings settings = new AccountSettings(this);
        
        // validate IMAP, which requires logging in and establishing an AUTHORIZED cx state
        bool imap_valid = false;
        Geary.Imap.ClientSession? imap_session = new Imap.ClientSession(settings.imap_endpoint, true);
        try {
            yield imap_session.connect_async(cancellable);
            yield imap_session.initiate_session_async(settings.imap_credentials, cancellable);
            
            // Connected and initiated, still need to be sure connection authorized
            string current_mailbox;
            if (imap_session.get_context(out current_mailbox) == Imap.ClientSession.Context.AUTHORIZED)
                imap_valid = true;
        } catch (Error err) {
            debug("Error validating IMAP account info: %s", err.message);
            
            // fall through so session can be disconnected
        }
        
        try {
            yield imap_session.disconnect_async(cancellable);
        } catch (Error err) {
            // ignored
        } finally {
            imap_session = null;
        }
        
        if (!imap_valid)
            return false;
        
        // SMTP is simpler, merely see if login works and done (throws an SmtpError if not)
        bool smtp_valid = false;
        Geary.Smtp.ClientSession? smtp_session = new Geary.Smtp.ClientSession(settings.smtp_endpoint);
        try {
            yield smtp_session.login_async(settings.smtp_credentials, cancellable);
            smtp_valid = true;
        } catch (Error err) {
            debug("Error validating SMTP account info: %s", err.message);
            
            // fall through so session can be disconnected
        }
        
        try {
            yield smtp_session.logout_async(cancellable);
        } catch (Error err) {
            // ignored
        } finally {
            smtp_session = null;
        }
        
        return smtp_valid;
    }

    public Endpoint get_imap_endpoint() throws EngineError {
        switch (service_provider) {
            case ServiceProvider.GMAIL:
                return ImapEngine.GmailAccount.IMAP_ENDPOINT;
            
            case ServiceProvider.YAHOO:
                return ImapEngine.YahooAccount.IMAP_ENDPOINT;
            
            case ServiceProvider.OTHER:
                Endpoint.Flags imap_flags = Endpoint.Flags.GRACEFUL_DISCONNECT;
                if (default_imap_server_ssl)
                    imap_flags |= Endpoint.Flags.SSL;
                if (default_imap_server_starttls)
                    imap_flags |= Endpoint.Flags.STARTTLS;
                
                return new Endpoint(default_imap_server_host, default_imap_server_port,
                    imap_flags, Imap.ClientConnection.RECOMMENDED_TIMEOUT_SEC);
            
            default:
                throw new EngineError.NOT_FOUND("Service provider of type %s not known",
                    service_provider.to_string());
        }
    }

    public Endpoint get_smtp_endpoint() throws EngineError {
        switch (service_provider) {
            case ServiceProvider.GMAIL:
                return ImapEngine.GmailAccount.SMTP_ENDPOINT;
            
            case ServiceProvider.YAHOO:
                return ImapEngine.YahooAccount.SMTP_ENDPOINT;
            
            case ServiceProvider.OTHER:
                Endpoint.Flags smtp_flags = Endpoint.Flags.GRACEFUL_DISCONNECT;
                if (default_smtp_server_ssl)
                    smtp_flags |= Endpoint.Flags.SSL;
                if (default_smtp_server_starttls)
                    smtp_flags |= Endpoint.Flags.STARTTLS;
                
                return new Endpoint(default_smtp_server_host, default_smtp_server_port,
                    smtp_flags, Smtp.ClientConnection.DEFAULT_TIMEOUT_SEC);
            
            default:
                throw new EngineError.NOT_FOUND("Service provider of type %s not known",
                    service_provider.to_string());
        }
    }

    public Geary.Account get_account() throws EngineError {
        AccountSettings settings = new AccountSettings(this);
        
        ImapDB.Account local_account = new ImapDB.Account(settings);
        Imap.Account remote_account = new Imap.Account(settings);
        
        switch (service_provider) {
            case ServiceProvider.GMAIL:
                return new ImapEngine.GmailAccount("Gmail account %s".printf(email),
                    settings, remote_account, local_account);
            
            case ServiceProvider.YAHOO:
                return new ImapEngine.YahooAccount("Yahoo account %s".printf(email),
                    settings, remote_account, local_account);
            
            case ServiceProvider.OTHER:
                return new ImapEngine.OtherAccount("Other account %s".printf(email),
                    settings, remote_account, local_account);
                
            default:
                throw new EngineError.NOT_FOUND("Service provider of type %s not known",
                    service_provider.to_string());
        }
    }
    
    private string get_string_value(KeyFile key_file, string group, string key, string def = "") {
        try {
            return key_file.get_value(group, key);
        } catch(KeyFileError err) {
            // Ignore.
        }
        
        return def;
    }
    
    private bool get_bool_value(KeyFile key_file, string group, string key, bool def = false) {
        try {
            return key_file.get_boolean(group, key);
        } catch(KeyFileError err) {
            // Ignore.
        }
        
        return def;
    }
    
    private uint16 get_uint16_value(KeyFile key_file, string group, string key, uint16 def = 0) {
        try {
            return (uint16) key_file.get_integer(group, key);
        } catch(KeyFileError err) {
            // Ignore.
        }
        
        return def;
    }
    
    public async void store_async(Cancellable? cancellable = null) {
        assert(file != null);
        
        if (!settings_dir.query_exists(cancellable)) {
            try {
                settings_dir.make_directory_with_parents();
            } catch (Error err) {
                error("Error creating settings directory for email '%s': %s", email,
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
        key_file.set_value(GROUP, IMAP_USERNAME_KEY, imap_credentials.user);
        key_file.set_boolean(GROUP, IMAP_REMEMBER_PASSWORD_KEY, imap_remember_password);
        key_file.set_value(GROUP, SMTP_USERNAME_KEY, smtp_credentials.user);
        key_file.set_boolean(GROUP, SMTP_REMEMBER_PASSWORD_KEY, smtp_remember_password);
        
        key_file.set_boolean(GROUP, IMAP_PIPELINE, imap_server_pipeline);

        if (service_provider == ServiceProvider.OTHER) {
            key_file.set_value(GROUP, IMAP_HOST, default_imap_server_host);
            key_file.set_integer(GROUP, IMAP_PORT, default_imap_server_port);
            key_file.set_boolean(GROUP, IMAP_SSL, default_imap_server_ssl);
            key_file.set_boolean(GROUP, IMAP_STARTTLS, default_imap_server_starttls);
            
            key_file.set_value(GROUP, SMTP_HOST, default_smtp_server_host);
            key_file.set_integer(GROUP, SMTP_PORT, default_smtp_server_port);
            key_file.set_boolean(GROUP, SMTP_SSL, default_smtp_server_ssl);
            key_file.set_boolean(GROUP, SMTP_STARTTLS, default_smtp_server_starttls);
        }
        
        string data = key_file.to_data();
        string new_etag;
        
        try {
            yield file.replace_contents_async(data.data, null, false, FileCreateFlags.NONE,
                cancellable, out new_etag);

            Geary.Engine.instance.add_account(this, true);
        } catch (Error err) {
            debug("Error writing to account info file: %s", err.message);
        }
    }
}
