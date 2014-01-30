/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class Geary.AccountInformation : BaseObject {
    public const string PROP_NICKNAME = "nickname"; // Name of nickname property.
    
    private const string GROUP = "AccountInformation";
    private const string REAL_NAME_KEY = "real_name";
    private const string NICKNAME_KEY = "nickname";
    private const string SERVICE_PROVIDER_KEY = "service_provider";
    private const string ORDINAL_KEY = "ordinal";
    private const string PREFETCH_PERIOD_DAYS_KEY = "prefetch_period_days";
    private const string IMAP_USERNAME_KEY = "imap_username";
    private const string IMAP_REMEMBER_PASSWORD_KEY = "imap_remember_password";
    private const string SMTP_USERNAME_KEY = "smtp_username";
    private const string SMTP_REMEMBER_PASSWORD_KEY = "smtp_remember_password";
    private const string IMAP_HOST = "imap_host";
    private const string IMAP_PORT = "imap_port";
    private const string IMAP_SSL = "imap_ssl";
    private const string IMAP_STARTTLS = "imap_starttls";
    private const string SMTP_HOST = "smtp_host";
    private const string SMTP_PORT = "smtp_port";
    private const string SMTP_SSL = "smtp_ssl";
    private const string SMTP_STARTTLS = "smtp_starttls";
    private const string SMTP_NOAUTH = "smtp_noauth";
    private const string SAVE_SENT_MAIL_KEY = "save_sent_mail";
    
    //
    // "Retired" keys
    //
    
    /*
     * key: "imap_pipeline"
     * value: bool
     */
    
    public const string SETTINGS_FILENAME = "geary.ini";
    public const int DEFAULT_PREFETCH_PERIOD_DAYS = 14;
    
    public static int default_ordinal = 0;
    
    internal File? settings_dir = null;
    internal File? file = null;
    
    // IMPORTANT: When adding new properties, be sure to add them to the copy method.
    
    public string real_name { get; set; }
    public string nickname { get; set; }
    public string email { get; set; }
    public Geary.ServiceProvider service_provider { get; set; }
    public int prefetch_period_days { get; set; }
    
    /**
     * Whether the user has requested that sent mail be saved.  Note that Geary
     * will only actively push sent mail when this AND allow_save_sent_mail()
     * are both true.
     */
    public bool save_sent_mail {
        // If we aren't allowed to save sent mail due to account type, we want
        // to return true here on the assumption that the account will save
        // sent mail for us, and thus the user can't disable sent mail from
        // being saved.
        get { return (allow_save_sent_mail() ? _save_sent_mail : true); }
        set { _save_sent_mail = value; }
    }
    
    // Order for display purposes.
    public int ordinal { get; set; }
    
    // These properties are only used if the service provider's account type does not override them.
    public string default_imap_server_host { get; set; }
    public uint16 default_imap_server_port  { get; set; }
    public bool default_imap_server_ssl  { get; set; }
    public bool default_imap_server_starttls  { get; set; }
    public string default_smtp_server_host  { get; set; }
    public uint16 default_smtp_server_port  { get; set; }
    public bool default_smtp_server_ssl  { get; set; }
    public bool default_smtp_server_starttls { get; set; }
    public bool default_smtp_server_noauth { get; set; }

    public Geary.Credentials imap_credentials { get; set; default = new Geary.Credentials(null, null); }
    public bool imap_remember_password { get; set; default = true; }
    public Geary.Credentials? smtp_credentials { get; set; default = new Geary.Credentials(null, null); }
    public bool smtp_remember_password { get; set; default = true; }
    
    private bool _save_sent_mail = true;
    
    // Used to create temporary AccountInformation objects.  (Note that these cannot be saved.)
    public AccountInformation.temp_copy(AccountInformation copy) {
        copy_from(copy);
    }
    
    // This constructor is used internally to load accounts from disk.
    internal AccountInformation.from_file(File directory) {
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
            nickname = get_string_value(key_file, GROUP, NICKNAME_KEY);
            imap_credentials.user = get_string_value(key_file, GROUP, IMAP_USERNAME_KEY, email);
            imap_remember_password = get_bool_value(key_file, GROUP, IMAP_REMEMBER_PASSWORD_KEY, true);
            smtp_credentials.user = get_string_value(key_file, GROUP, SMTP_USERNAME_KEY, email);
            smtp_remember_password = get_bool_value(key_file, GROUP, SMTP_REMEMBER_PASSWORD_KEY, true);
            service_provider = Geary.ServiceProvider.from_string(get_string_value(key_file, GROUP,
                SERVICE_PROVIDER_KEY, Geary.ServiceProvider.GMAIL.to_string()));
            prefetch_period_days = get_int_value(key_file, GROUP, PREFETCH_PERIOD_DAYS_KEY,
                DEFAULT_PREFETCH_PERIOD_DAYS);
            save_sent_mail = get_bool_value(key_file, GROUP, SAVE_SENT_MAIL_KEY, true);
            ordinal = get_int_value(key_file, GROUP, ORDINAL_KEY, default_ordinal++);
            
            if (ordinal >= default_ordinal)
                default_ordinal = ordinal + 1;
            
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
                default_smtp_server_noauth = get_bool_value(key_file, GROUP, SMTP_NOAUTH, false);
                
                if (default_smtp_server_noauth) {
                    // Make sure the SMTP credentials are unset.
                    smtp_credentials = null;
                }
            }
        }
    }
    
    // Copies all data from the "from" object into this one.
    public void copy_from(AccountInformation from) {
        real_name = from.real_name;
        nickname = from.nickname;
        email = from.email;
        service_provider = from.service_provider;
        prefetch_period_days = from.prefetch_period_days;
        save_sent_mail = from.save_sent_mail;
        ordinal = from.ordinal;
        default_imap_server_host = from.default_imap_server_host;
        default_imap_server_port = from.default_imap_server_port;
        default_imap_server_ssl = from.default_imap_server_ssl;
        default_imap_server_starttls = from.default_imap_server_starttls;
        default_smtp_server_host = from.default_smtp_server_host;
        default_smtp_server_port = from.default_smtp_server_port;
        default_smtp_server_ssl = from.default_smtp_server_ssl;
        default_smtp_server_starttls = from.default_smtp_server_starttls;
        default_smtp_server_noauth = from.default_smtp_server_noauth;
        imap_credentials = from.imap_credentials;
        imap_remember_password = from.imap_remember_password;
        smtp_credentials = from.smtp_credentials;
        smtp_remember_password = from.smtp_remember_password;
    }
    
    /**
     * Return whether this account allows setting the save_sent_mail option.
     * If not, save_sent_mail will always be true and setting it will be
     * ignored.
     */
    public bool allow_save_sent_mail() {
        // We should never push mail to Gmail, since its servers automatically
        // push sent mail to the sent mail folder.
        return service_provider != ServiceProvider.GMAIL;
    }
    
    /**
     * Fetch the passwords for the given services.  For each service, if the
     * password is unset, use get_passwords_async() first; if the password is
     * set or it's not in the key store, use prompt_passwords_async().  Return
     * true if all passwords were retrieved from the key store or the user
     * proceeded normally if/when prompted, false if the user tried to cancel
     * the prompt.
     *
     * If force_request is set to true, a prompt will appear regardless.
     */
    public async bool fetch_passwords_async(CredentialsMediator.ServiceFlag services,
        bool force_request = false) throws Error {
        if (force_request) {
            // Delete the current password(s).
            if (services.has_imap()) {
                yield Geary.Engine.instance.authentication_mediator.clear_password_async(
                    CredentialsMediator.Service.IMAP, email);
                
                if (imap_credentials != null)
                    imap_credentials.pass = null;
            } else if (services.has_smtp()) {
                yield Geary.Engine.instance.authentication_mediator.clear_password_async(
                    CredentialsMediator.Service.SMTP, email);
                
                if (smtp_credentials != null)
                    smtp_credentials.pass = null;
            }
        }
        
        // Only call get_passwords on anything that hasn't been set
        // (incorrectly) previously.
        CredentialsMediator.ServiceFlag get_services = 0;
        if (services.has_imap() && !imap_credentials.is_complete())
            get_services |= CredentialsMediator.ServiceFlag.IMAP;
        
        if (services.has_smtp() && smtp_credentials != null && !smtp_credentials.is_complete())
            get_services |= CredentialsMediator.ServiceFlag.SMTP;
        
        CredentialsMediator.ServiceFlag unset_services = services;
        if (get_services != 0)
            unset_services = yield get_passwords_async(get_services);
        else
            return true;
        
        if (unset_services == 0)
            return true;
        
        return yield prompt_passwords_async(unset_services);
    }
    
    private void check_mediator_instance() throws EngineError {
        if (Geary.Engine.instance.authentication_mediator == null)
            throw new EngineError.OPEN_REQUIRED(
                "Geary.Engine instance needs to be open with a valid Geary.CredentialsMediator");
    }
    
    private void set_imap_password(string imap_password) {
        // Don't just update the pass field, because we need imap_credentials
        // itself to change so callers can bind to its changed signal.
        imap_credentials = new Credentials(imap_credentials.user, imap_password);
    }
    
    private void set_smtp_password(string smtp_password) {
        // See above.  Same argument.
        smtp_credentials = new Credentials(smtp_credentials.user, smtp_password);
    }
    
    /**
     * Use Engine's authentication mediator to retrieve the passwords for the
     * given services.  The passwords will be stored in the appropriate
     * credentials in this instance.  Return any services that could *not* be
     * retrieved from the key store (in which case you may want to call
     * prompt_passwords_async() on the return value), or 0 if all were
     * retrieved.
     */
    public async CredentialsMediator.ServiceFlag get_passwords_async(
        CredentialsMediator.ServiceFlag services) throws Error {
        check_mediator_instance();
        
        CredentialsMediator mediator = Geary.Engine.instance.authentication_mediator;
        CredentialsMediator.ServiceFlag failed_services = 0;
        
        if (services.has_imap()) {
            string? imap_password = yield mediator.get_password_async(
                CredentialsMediator.Service.IMAP, imap_credentials.user);
            
            if (imap_password != null)
                set_imap_password(imap_password);
             else
                failed_services |= CredentialsMediator.ServiceFlag.IMAP;
        }
        
        if (services.has_smtp() && smtp_credentials != null) {
            string? smtp_password = yield mediator.get_password_async(
                CredentialsMediator.Service.SMTP, smtp_credentials.user);
            
            if (smtp_password != null)
                set_smtp_password(smtp_password);
            else
                failed_services |= CredentialsMediator.ServiceFlag.SMTP;
        }
        
        return failed_services;
    }
    
    /**
     * Use the Engine's authentication mediator to prompt for the passwords for
     * the given services.  The passwords will be stored in the appropriate
     * credentials in this instance.  After the prompt, the passwords will be
     * updated in the key store using update_stored_passwords_async().  Return
     * whether the user proceeded normally (false if they tried to cancel the
     * prompt).
     */
    public async bool prompt_passwords_async(
        CredentialsMediator.ServiceFlag services) throws Error {
        check_mediator_instance();
        
        string? imap_password, smtp_password;
        bool imap_remember_password, smtp_remember_password;
        
        if (smtp_credentials == null)
            services &= ~CredentialsMediator.ServiceFlag.SMTP;
        
        if (!yield Geary.Engine.instance.authentication_mediator.prompt_passwords_async(
            services, this, out imap_password, out smtp_password,
            out imap_remember_password, out smtp_remember_password))
            return false;
        
        if (services.has_imap()) {
            set_imap_password(imap_password);
            this.imap_remember_password = imap_remember_password;
        }
        
        if (services.has_smtp()) {
            set_smtp_password(smtp_password);
            this.smtp_remember_password = smtp_remember_password;
        }

        yield update_stored_passwords_async(services);
        
        return true;
    }
    
    /**
     * Use the Engine's authentication mediator to set or clear the passwords
     * for the given services in the key store.
     */
    public async void update_stored_passwords_async(
        CredentialsMediator.ServiceFlag services) throws Error {
        check_mediator_instance();
        
        CredentialsMediator mediator = Geary.Engine.instance.authentication_mediator;
        
        if (services.has_imap()) {
            if (imap_remember_password) {
                yield mediator.set_password_async(
                    CredentialsMediator.Service.IMAP, imap_credentials);
            } else {
                yield mediator.clear_password_async(
                    CredentialsMediator.Service.IMAP, imap_credentials.user);
            }
        }
        
        if (services.has_smtp() && smtp_credentials != null) {
            if (smtp_remember_password) {
                yield mediator.set_password_async(
                    CredentialsMediator.Service.SMTP, smtp_credentials);
            } else {
                yield mediator.clear_password_async(
                    CredentialsMediator.Service.SMTP, smtp_credentials.user);
            }
        }
    }
    
    public Endpoint get_imap_endpoint() {
        switch (service_provider) {
            case ServiceProvider.GMAIL:
                return ImapEngine.GmailAccount.IMAP_ENDPOINT;
            
            case ServiceProvider.YAHOO:
                return ImapEngine.YahooAccount.IMAP_ENDPOINT;
            
            case ServiceProvider.OUTLOOK:
                return ImapEngine.OutlookAccount.IMAP_ENDPOINT;
            
            case ServiceProvider.OTHER:
                Endpoint.Flags imap_flags = Endpoint.Flags.GRACEFUL_DISCONNECT;
                if (default_imap_server_ssl)
                    imap_flags |= Endpoint.Flags.SSL;
                if (default_imap_server_starttls)
                    imap_flags |= Endpoint.Flags.STARTTLS;
                
                return new Endpoint(default_imap_server_host, default_imap_server_port,
                    imap_flags, Imap.ClientConnection.RECOMMENDED_TIMEOUT_SEC);
            
            default:
                assert_not_reached();
        }
    }

    public Endpoint get_smtp_endpoint() {
        switch (service_provider) {
            case ServiceProvider.GMAIL:
                return ImapEngine.GmailAccount.SMTP_ENDPOINT;
            
            case ServiceProvider.YAHOO:
                return ImapEngine.YahooAccount.SMTP_ENDPOINT;
            
            case ServiceProvider.OUTLOOK:
                return ImapEngine.OutlookAccount.SMTP_ENDPOINT;
            
            case ServiceProvider.OTHER:
                Endpoint.Flags smtp_flags = Endpoint.Flags.GRACEFUL_DISCONNECT;
                if (default_smtp_server_ssl)
                    smtp_flags |= Endpoint.Flags.SSL;
                if (default_smtp_server_starttls)
                    smtp_flags |= Endpoint.Flags.STARTTLS;
                
                return new Endpoint(default_smtp_server_host, default_smtp_server_port,
                    smtp_flags, Smtp.ClientConnection.DEFAULT_TIMEOUT_SEC);
            
            default:
                assert_not_reached();
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
    
    private int get_int_value(KeyFile key_file, string group, string key, int def = 0) {
        try {
            return key_file.get_integer(group, key);
        } catch(KeyFileError err) {
            // Ignore.
        }
        
        return def;
    }
    
    private uint16 get_uint16_value(KeyFile key_file, string group, string key, uint16 def = 0) {
        return (uint16) get_int_value(key_file, group, key);
    }
    
    public async void store_async(Cancellable? cancellable = null) {
        if (file == null || settings_dir == null) {
            warning("Cannot save account, no file set.\n");
            return;
        }
        
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
        key_file.set_value(GROUP, NICKNAME_KEY, nickname);
        key_file.set_value(GROUP, SERVICE_PROVIDER_KEY, service_provider.to_string());
        key_file.set_integer(GROUP, ORDINAL_KEY, ordinal);
        key_file.set_value(GROUP, IMAP_USERNAME_KEY, imap_credentials.user);
        key_file.set_boolean(GROUP, IMAP_REMEMBER_PASSWORD_KEY, imap_remember_password);
        if (smtp_credentials != null)
            key_file.set_value(GROUP, SMTP_USERNAME_KEY, smtp_credentials.user);
        key_file.set_boolean(GROUP, SMTP_REMEMBER_PASSWORD_KEY, smtp_remember_password);
        key_file.set_integer(GROUP, PREFETCH_PERIOD_DAYS_KEY, prefetch_period_days);
        key_file.set_boolean(GROUP, SAVE_SENT_MAIL_KEY, save_sent_mail);
        
        if (service_provider == ServiceProvider.OTHER) {
            key_file.set_value(GROUP, IMAP_HOST, default_imap_server_host);
            key_file.set_integer(GROUP, IMAP_PORT, default_imap_server_port);
            key_file.set_boolean(GROUP, IMAP_SSL, default_imap_server_ssl);
            key_file.set_boolean(GROUP, IMAP_STARTTLS, default_imap_server_starttls);
            
            key_file.set_value(GROUP, SMTP_HOST, default_smtp_server_host);
            key_file.set_integer(GROUP, SMTP_PORT, default_smtp_server_port);
            key_file.set_boolean(GROUP, SMTP_SSL, default_smtp_server_ssl);
            key_file.set_boolean(GROUP, SMTP_STARTTLS, default_smtp_server_starttls);
            key_file.set_boolean(GROUP, SMTP_NOAUTH, default_smtp_server_noauth);
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
    
    public async void clear_stored_passwords_async(
        CredentialsMediator.ServiceFlag services) throws Error {
        Error? return_error = null;
        check_mediator_instance();
        CredentialsMediator mediator = Geary.Engine.instance.authentication_mediator;
        
        try {
            if (services.has_imap()) {
                yield mediator.clear_password_async(
                    CredentialsMediator.Service.IMAP, imap_credentials.user);
            }
        } catch (Error e) {
            return_error = e;
        }
        
        try {
            if (services.has_smtp() && smtp_credentials != null) {
                yield mediator.clear_password_async(
                    CredentialsMediator.Service.SMTP, smtp_credentials.user);
            }
        } catch (Error e) {
            return_error = e;
        }
        
        if (return_error != null)
            throw return_error;
    }
    
    /**
     * Deletes an account from disk.  This is used by Geary.Engine and should not
     * normally be invoked directly.
     */
    internal async void remove_async(Cancellable? cancellable = null) {
        if (file == null || settings_dir == null) {
            warning("Cannot remove account; nothing to remove\n");
            return;
        }
        
        try {
            yield clear_stored_passwords_async(CredentialsMediator.ServiceFlag.IMAP
                | CredentialsMediator.ServiceFlag.SMTP);
        } catch (Error e) {
            debug("Error clearing SMTP password: %s", e.message);
        }
        
        // Delete files.
        yield Files.recursive_delete_async(settings_dir, cancellable);
    }
    
    /**
     * Returns a MailboxAddress object for this account.
     */
    public RFC822.MailboxAddress get_mailbox_address() {
        return new RFC822.MailboxAddress(real_name, email);
    }
    
    /**
     * Returns a MailboxAddresses object with this mailbox address.
     */
    public RFC822.MailboxAddresses get_from() {
        return new RFC822.MailboxAddresses.single(get_mailbox_address());
    }
    
    public static int compare_ascending(AccountInformation a, AccountInformation b) {
        int diff = a.ordinal - b.ordinal;
        if (diff != 0)
            return diff;
        
        // Stabilize on nickname, which should always be unique.
        return a.nickname.collate(b.nickname);
    }
    
    // Returns true if this is a copy.
    public bool is_copy() {
        return file == null;
    }
}
