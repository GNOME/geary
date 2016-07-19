/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class Geary.AccountInformation : BaseObject {
    public const string PROP_NICKNAME = "nickname"; // Name of nickname property.
    
    private const string GROUP = "AccountInformation";
    private const string REAL_NAME_KEY = "real_name";
    private const string NICKNAME_KEY = "nickname";
    private const string PRIMARY_EMAIL_KEY = "primary_email";
    private const string ALTERNATE_EMAILS_KEY = "alternate_emails";
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
    private const string SMTP_USE_IMAP_CREDENTIALS = "smtp_use_imap_credentials";
    private const string SMTP_NOAUTH = "smtp_noauth";
    private const string SAVE_SENT_MAIL_KEY = "save_sent_mail";
    private const string DRAFTS_FOLDER_KEY = "drafts_folder";
    private const string SENT_MAIL_FOLDER_KEY = "sent_mail_folder";
    private const string SPAM_FOLDER_KEY = "spam_folder";
    private const string TRASH_FOLDER_KEY = "trash_folder";
    private const string ARCHIVE_FOLDER_KEY = "archive_folder";
    private const string SAVE_DRAFTS_KEY = "save_drafts";
    private const string USE_EMAIL_SIGNATURE_KEY = "use_email_signature";
    private const string EMAIL_SIGNATURE_KEY = "email_signature";
    
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
    
    private static Gee.HashMap<string, Geary.Endpoint>? known_endpoints = null;
    
    /**
     * Location account information is stored (as well as other data, including database and
     * attachment files.
     */
    public File? config_dir { get; private set; default = null; }
    public File? data_dir { get; private set; default = null; }

    internal File? file = null;

    //
    // IMPORTANT: When adding new properties, be sure to add them to the copy method.
    //

    /**
     * Unique identifier for this account.
     *
     * This string's value should be treated as an opaque, private
     * implementation detail and not parsed at all. For older accounts
     * it will be an email address, for newer accounts it will be
     * something else.
     */
    public string id { get; private set; }

    /**
     * User's name for the {@link get_primary_mailbox_address}.
     */
    public string real_name { get; set; }
    
    /**
     * User label for primary account (not transmitted on wire or used in correspondence).
     */
    public string nickname { get; set; }

    /**
     * The default email address for the account.
     */
    public Geary.RFC822.MailboxAddress primary_mailbox  { get; set; }

    /**
     * A list of additional email addresses this account accepts.
     *
     * Use {@link add_alternate_mailbox} or {@link replace_alternate_mailboxes} rather than edit
     * this collection directly.
     *
     * @see get_all_mailboxes
     */
    public Gee.List<Geary.RFC822.MailboxAddress>? alternate_mailboxes { get; private set; default = null; }

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
    public bool default_smtp_use_imap_credentials { get; set; }
    public bool default_smtp_server_noauth { get; set; }
    public bool use_email_signature { get; set; }
    public string email_signature {get; set; } 
    
    public Geary.FolderPath? drafts_folder_path { get; set; default = null; }
    public Geary.FolderPath? sent_mail_folder_path { get; set; default = null; }
    public Geary.FolderPath? spam_folder_path { get; set; default = null; }
    public Geary.FolderPath? trash_folder_path { get; set; default = null; }
    public Geary.FolderPath? archive_folder_path { get; set; default = null; }

    public Geary.Credentials imap_credentials { get; set; default = new Geary.Credentials(null, null); }
    public bool imap_remember_password { get; set; default = true; }
    public Geary.Credentials? smtp_credentials { get; set; default = new Geary.Credentials(null, null); }
    public bool smtp_remember_password { get; set; default = true; }
    
    public bool save_drafts { get; set; default = true; }
    
    private bool _save_sent_mail = true;
    private Endpoint? imap_endpoint = null;
    private Endpoint? smtp_endpoint = null;
    
    /**
     * Indicates the supplied {@link Endpoint} has reported TLS certificate warnings during
     * connection.
     *
     * Since this {@link Endpoint} persists for the lifetime of the {@link AccountInformation},
     * marking it as trusted once will survive the application session.  It is up to the caller to
     * pin the certificate appropriately if the user does not want to receive these warnings in
     * the future.
     */
    public signal void untrusted_host(Endpoint endpoint, Endpoint.SecurityType security,
        TlsConnection cx, Service service);

    // Used to create temporary AccountInformation objects.  (Note that these cannot be saved.)
    public AccountInformation.temp_copy(AccountInformation copy) {
        copy_from(copy);
    }

    // This constructor is used internally to load accounts from disk.
    internal AccountInformation.from_file(File config_directory, File data_directory) {
        this.id = config_directory.get_basename();
        this.config_dir = config_directory;
        this.data_dir = data_directory;
        this.file = config_dir.get_child(SETTINGS_FILENAME);

        KeyFile key_file = new KeyFile();
        try {
            key_file.load_from_file(file.get_path() ?? "", KeyFileFlags.NONE);
        } catch (FileError err) {
            // See comment in next catch block.
        } catch (KeyFileError err) {
            // It's no big deal if we couldn't load the key file -- just means we give you the defaults.
        } finally {
            this.real_name = get_string_value(key_file, GROUP, REAL_NAME_KEY);
            this.nickname = get_string_value(key_file, GROUP, NICKNAME_KEY);

            string primary_email = get_string_value(key_file, GROUP, PRIMARY_EMAIL_KEY);
            this.primary_mailbox = new RFC822.MailboxAddress(this.real_name, primary_email);

            // Store alternate emails in a list of case-insensitive strings
            Gee.List<string> alt_email_list = get_string_list_value(key_file, GROUP, ALTERNATE_EMAILS_KEY);
            if (alt_email_list.size != 0) {
                foreach (string alt_email in alt_email_list) {
                    RFC822.MailboxAddresses mailboxes = new RFC822.MailboxAddresses.from_rfc822_string(alt_email);
                    foreach (RFC822.MailboxAddress mailbox in mailboxes.get_all())
                        add_alternate_mailbox(mailbox);
                }
            }

            this.imap_credentials.user = get_string_value(key_file, GROUP, IMAP_USERNAME_KEY, primary_email);
            this.imap_remember_password = get_bool_value(key_file, GROUP, IMAP_REMEMBER_PASSWORD_KEY, true);
            this.smtp_credentials.user = get_string_value(key_file, GROUP, SMTP_USERNAME_KEY, primary_email);
            this.smtp_remember_password = get_bool_value(key_file, GROUP, SMTP_REMEMBER_PASSWORD_KEY, true);
            this.service_provider = Geary.ServiceProvider.from_string(get_string_value(key_file, GROUP,
                SERVICE_PROVIDER_KEY, Geary.ServiceProvider.GMAIL.to_string()));
            this.prefetch_period_days = get_int_value(key_file, GROUP, PREFETCH_PERIOD_DAYS_KEY,
                DEFAULT_PREFETCH_PERIOD_DAYS);
            this.save_sent_mail = get_bool_value(key_file, GROUP, SAVE_SENT_MAIL_KEY, true);
            this.ordinal = get_int_value(key_file, GROUP, ORDINAL_KEY, AccountInformation.default_ordinal++);
            this.use_email_signature = get_bool_value(key_file, GROUP, USE_EMAIL_SIGNATURE_KEY);
            this.email_signature = get_escaped_string(key_file, GROUP, EMAIL_SIGNATURE_KEY);

            if (this.ordinal >= AccountInformation.default_ordinal)
                AccountInformation.default_ordinal = this.ordinal + 1;

            if (service_provider == ServiceProvider.OTHER) {
                this.default_imap_server_host = get_string_value(key_file, GROUP, IMAP_HOST);
                this.default_imap_server_port = get_uint16_value(key_file, GROUP, IMAP_PORT,
                    Imap.ClientConnection.DEFAULT_PORT_SSL);
                this.default_imap_server_ssl = get_bool_value(key_file, GROUP, IMAP_SSL, true);
                this.default_imap_server_starttls = get_bool_value(key_file, GROUP, IMAP_STARTTLS, false);

                this.default_smtp_server_host = get_string_value(key_file, GROUP, SMTP_HOST);
                this.default_smtp_server_port = get_uint16_value(key_file, GROUP, SMTP_PORT,
                    Geary.Smtp.ClientConnection.DEFAULT_PORT_SSL);
                this.default_smtp_server_ssl = get_bool_value(key_file, GROUP, SMTP_SSL, true);
                this.default_smtp_server_starttls = get_bool_value(key_file, GROUP, SMTP_STARTTLS, false);
                this.default_smtp_use_imap_credentials = get_bool_value(key_file, GROUP, SMTP_USE_IMAP_CREDENTIALS, false);
                this.default_smtp_server_noauth = get_bool_value(key_file, GROUP, SMTP_NOAUTH, false);

                if (default_smtp_server_noauth) {
                    this.smtp_credentials = null;
                } else if (default_smtp_use_imap_credentials) {
                    this.smtp_credentials.user = imap_credentials.user;
                    this.smtp_credentials.pass = imap_credentials.pass;
                }
            }

            this.drafts_folder_path = build_folder_path(get_string_list_value(
                key_file, GROUP, DRAFTS_FOLDER_KEY));
            this.sent_mail_folder_path = build_folder_path(get_string_list_value(
                key_file, GROUP, SENT_MAIL_FOLDER_KEY));
            this.spam_folder_path = build_folder_path(get_string_list_value(
                key_file, GROUP, SPAM_FOLDER_KEY));
            this.trash_folder_path = build_folder_path(get_string_list_value(
                key_file, GROUP, TRASH_FOLDER_KEY));
            this.archive_folder_path = build_folder_path(get_string_list_value(
                key_file, GROUP, ARCHIVE_FOLDER_KEY));

            this.save_drafts = get_bool_value(key_file, GROUP, SAVE_DRAFTS_KEY, true);
        }
    }

    ~AccountInformation() {
        if (imap_endpoint != null)
            imap_endpoint.untrusted_host.disconnect(on_imap_untrusted_host);
        
        if (smtp_endpoint != null)
            smtp_endpoint.untrusted_host.disconnect(on_smtp_untrusted_host);
    }
    
    internal static void init() {
        known_endpoints = new Gee.HashMap<string, Geary.Endpoint>();
    }
    
    private static Geary.Endpoint get_shared_endpoint(Service service, Endpoint endpoint) {
        string key = "%s/%s:%u".printf(service.user_label(), endpoint.remote_address.hostname,
            endpoint.remote_address.port);
        
        // if already known, prefer it over this one
        if (known_endpoints.has_key(key))
            return known_endpoints.get(key);
        
        // save for future use and return this one
        known_endpoints.set(key, endpoint);
        
        return endpoint;
    }
    
    // Copies all data from the "from" object into this one.
    public void copy_from(AccountInformation from) {
        this.id = from.id;
        this.real_name = from.real_name;
        this.nickname = from.nickname;
        this.primary_mailbox = from.primary_mailbox;
        if (from.alternate_mailboxes != null) {
            foreach (RFC822.MailboxAddress alternate_mailbox in from.alternate_mailboxes)
                add_alternate_mailbox(alternate_mailbox);
        }
        this.service_provider = from.service_provider;
        this.prefetch_period_days = from.prefetch_period_days;
        this.save_sent_mail = from.save_sent_mail;
        this.ordinal = from.ordinal;
        this.default_imap_server_host = from.default_imap_server_host;
        this.default_imap_server_port = from.default_imap_server_port;
        this.default_imap_server_ssl = from.default_imap_server_ssl;
        this.default_imap_server_starttls = from.default_imap_server_starttls;
        this.default_smtp_server_host = from.default_smtp_server_host;
        this.default_smtp_server_port = from.default_smtp_server_port;
        this.default_smtp_server_ssl = from.default_smtp_server_ssl;
        this.default_smtp_server_starttls = from.default_smtp_server_starttls;
        this.default_smtp_use_imap_credentials = from.default_smtp_use_imap_credentials;
        this.default_smtp_server_noauth = from.default_smtp_server_noauth;
        this.imap_credentials = from.imap_credentials;
        this.imap_remember_password = from.imap_remember_password;
        this.smtp_credentials = from.smtp_credentials;
        this.smtp_remember_password = from.smtp_remember_password;
        this.drafts_folder_path = from.drafts_folder_path;
        this.sent_mail_folder_path = from.sent_mail_folder_path;
        this.spam_folder_path = from.spam_folder_path;
        this.trash_folder_path = from.trash_folder_path;
        this.archive_folder_path = from.archive_folder_path;
        this.save_drafts = from.save_drafts;
        this.use_email_signature = from.use_email_signature;
        this.email_signature = from.email_signature;
    }

    /**
     * Return a list of the primary and all alternate email addresses.
     */
    public Gee.List<Geary.RFC822.MailboxAddress> get_all_mailboxes() {
        Gee.ArrayList<RFC822.MailboxAddress> all = new Gee.ArrayList<RFC822.MailboxAddress>();

        all.add(this.primary_mailbox);

        if (alternate_mailboxes != null)
            all.add_all(alternate_mailboxes);
        
        return all;
    }
    
    /**
     * Add an alternate email address to the account.
     *
     * Duplicates will be ignored.
     */
    public void add_alternate_mailbox(Geary.RFC822.MailboxAddress mailbox) {
        if (alternate_mailboxes == null)
            alternate_mailboxes = new Gee.ArrayList<RFC822.MailboxAddress>();
        
        if (!alternate_mailboxes.contains(mailbox))
            alternate_mailboxes.add(mailbox);
    }
    
    /**
     * Replaces the list of alternate email addresses with the supplied collection.
     *
     * Duplicates will be ignored.
     */
    public void replace_alternate_mailboxes(Gee.Collection<Geary.RFC822.MailboxAddress>? mailboxes) {
        alternate_mailboxes = null;
        
        if (mailboxes == null || mailboxes.size == 0)
            return;
        
        foreach (RFC822.MailboxAddress mailbox in mailboxes)
            add_alternate_mailbox(mailbox);
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
     * Gets the path used when Geary has found or created a special folder for
     * this account.  This will be null if Geary has always been told about the
     * special folders by the server, and hasn't had to go looking for them.
     * Only the DRAFTS, SENT, SPAM, and TRASH special folder types are valid to
     * pass to this function.
     */
    public Geary.FolderPath? get_special_folder_path(Geary.SpecialFolderType special) {
        switch (special) {
            case Geary.SpecialFolderType.DRAFTS:
                return drafts_folder_path;
            
            case Geary.SpecialFolderType.SENT:
                return sent_mail_folder_path;
            
            case Geary.SpecialFolderType.SPAM:
                return spam_folder_path;
            
            case Geary.SpecialFolderType.TRASH:
                return trash_folder_path;

            case Geary.SpecialFolderType.ARCHIVE:
                return archive_folder_path;
            
            default:
                assert_not_reached();
        }
    }
    
    /**
     * Sets the path Geary will look for or create a special folder.  This is
     * only obeyed if the server doesn't tell Geary which folders are special.
     * Only the DRAFTS, SENT, SPAM, and TRASH special folder types are valid to
     * pass to this function.
     */
    public void set_special_folder_path(Geary.SpecialFolderType special, Geary.FolderPath? path) {
        switch (special) {
            case Geary.SpecialFolderType.DRAFTS:
                drafts_folder_path = path;
            break;
            
            case Geary.SpecialFolderType.SENT:
                sent_mail_folder_path = path;
            break;
            
            case Geary.SpecialFolderType.SPAM:
                spam_folder_path = path;
            break;
            
            case Geary.SpecialFolderType.TRASH:
                trash_folder_path = path;
            break;

            case Geary.SpecialFolderType.ARCHIVE:
                archive_folder_path = path;
            break;
            
            default:
                assert_not_reached();
        }
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
    public async bool fetch_passwords_async(ServiceFlag services,
        bool force_request = false) throws Error {
        if (force_request) {
            // Delete the current password(s).
            if (services.has_imap()) {
                yield Geary.Engine.instance.authentication_mediator.clear_password_async(
                    Service.IMAP, this);
                
                if (imap_credentials != null)
                    imap_credentials.pass = null;
            } else if (services.has_smtp()) {
                yield Geary.Engine.instance.authentication_mediator.clear_password_async(
                    Service.SMTP, this);
                
                if (smtp_credentials != null)
                    smtp_credentials.pass = null;
            }
        }
        
        // Only call get_passwords on anything that hasn't been set
        // (incorrectly) previously.
        ServiceFlag get_services = 0;
        if (services.has_imap() && !imap_credentials.is_complete())
            get_services |= ServiceFlag.IMAP;
        
        if (services.has_smtp() && smtp_credentials != null && !smtp_credentials.is_complete())
            get_services |= ServiceFlag.SMTP;
        
        ServiceFlag unset_services = services;
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
    public async ServiceFlag get_passwords_async(ServiceFlag services) throws Error {
        check_mediator_instance();
        
        CredentialsMediator mediator = Geary.Engine.instance.authentication_mediator;
        ServiceFlag failed_services = 0;
        
        if (services.has_imap()) {
            string? imap_password = yield mediator.get_password_async(Service.IMAP, this);
            
            if (imap_password != null)
                set_imap_password(imap_password);
             else
                failed_services |= ServiceFlag.IMAP;
        }
        
        if (services.has_smtp() && smtp_credentials != null) {
            string? smtp_password = yield mediator.get_password_async(Service.SMTP, this);
            
            if (smtp_password != null)
                set_smtp_password(smtp_password);
            else
                failed_services |= ServiceFlag.SMTP;
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
    public async bool prompt_passwords_async(ServiceFlag services) throws Error {
        check_mediator_instance();
        
        string? imap_password, smtp_password;
        bool imap_remember_password, smtp_remember_password;
        
        if (smtp_credentials == null)
            services &= ~ServiceFlag.SMTP;
        
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
    public async void update_stored_passwords_async(ServiceFlag services) throws Error {
        check_mediator_instance();
        
        CredentialsMediator mediator = Geary.Engine.instance.authentication_mediator;
        
        if (services.has_imap()) {
            if (imap_remember_password)
                yield mediator.set_password_async(Service.IMAP, this);
            else
                yield mediator.clear_password_async(Service.IMAP, this);
        }
        
        if (services.has_smtp() && smtp_credentials != null) {
            if (smtp_remember_password)
                yield mediator.set_password_async(Service.SMTP, this);
            else
                yield mediator.clear_password_async(Service.SMTP, this);
        }
    }
    
    /**
     * Returns the {@link Endpoint} for the account's IMAP service.
     *
     * The Endpoint instance is guaranteed to be the same for the lifetime of the
     * {@link AccountInformation} instance, which is in turn guaranteed to be the same for the
     * duration of the application session.
     */
    public Endpoint get_imap_endpoint() {
        if (imap_endpoint != null)
            return imap_endpoint;
        
        switch (service_provider) {
            case ServiceProvider.GMAIL:
                imap_endpoint = ImapEngine.GmailAccount.generate_imap_endpoint();
            break;
            
            case ServiceProvider.YAHOO:
                imap_endpoint = ImapEngine.YahooAccount.generate_imap_endpoint();
            break;
            
            case ServiceProvider.OUTLOOK:
                imap_endpoint = ImapEngine.OutlookAccount.generate_imap_endpoint();
            break;
            
            case ServiceProvider.OTHER:
                Endpoint.Flags imap_flags = Endpoint.Flags.NONE;
                if (default_imap_server_ssl)
                    imap_flags |= Endpoint.Flags.SSL;
                if (default_imap_server_starttls)
                    imap_flags |= Endpoint.Flags.STARTTLS;
                
                imap_endpoint = new Endpoint(default_imap_server_host, default_imap_server_port,
                    imap_flags, Imap.ClientConnection.RECOMMENDED_TIMEOUT_SEC);
            break;
            
            default:
                assert_not_reached();
        }
        
        // look for existing one in the global pool; want to use that because Endpoint is mutable
        // and signalled in such a way that it's better to share them
        imap_endpoint = get_shared_endpoint(Service.IMAP, imap_endpoint);
        
        // bind shared Endpoint signal to this AccountInformation's signal
        imap_endpoint.untrusted_host.connect(on_imap_untrusted_host);
        
        return imap_endpoint;
    }
    
    private void on_imap_untrusted_host(Endpoint endpoint, Endpoint.SecurityType security,
        TlsConnection cx) {
        untrusted_host(endpoint, security, cx, Service.IMAP);
    }
    
    /**
     * Returns the {@link Endpoint} for the account's SMTP service.
     *
     * The Endpoint instance is guaranteed to be the same for the lifetime of the
     * {@link AccountInformation} instance, which is in turn guaranteed to be the same for the
     * duration of the application session.
     */
    public Endpoint get_smtp_endpoint() {
        if (smtp_endpoint != null)
            return smtp_endpoint;
        
        switch (service_provider) {
            case ServiceProvider.GMAIL:
                smtp_endpoint = ImapEngine.GmailAccount.generate_smtp_endpoint();
            break;
            
            case ServiceProvider.YAHOO:
                smtp_endpoint = ImapEngine.YahooAccount.generate_smtp_endpoint();
            break;
            
            case ServiceProvider.OUTLOOK:
                smtp_endpoint = ImapEngine.OutlookAccount.generate_smtp_endpoint();
            break;
            
            case ServiceProvider.OTHER:
                Endpoint.Flags smtp_flags = Endpoint.Flags.NONE;
                if (default_smtp_server_ssl)
                    smtp_flags |= Endpoint.Flags.SSL;
                if (default_smtp_server_starttls)
                    smtp_flags |= Endpoint.Flags.STARTTLS;
                
                smtp_endpoint = new Endpoint(default_smtp_server_host, default_smtp_server_port,
                    smtp_flags, Smtp.ClientConnection.DEFAULT_TIMEOUT_SEC);
            break;
            
            default:
                assert_not_reached();
        }
        
        // look for existing one in the global pool; want to use that because Endpoint is mutable
        // and signalled in such a way that it's better to share them
        smtp_endpoint = get_shared_endpoint(Service.SMTP, smtp_endpoint);
        
        // bind shared Endpoint signal to this AccountInformation's signal
        smtp_endpoint.untrusted_host.connect(on_smtp_untrusted_host);
        
        return smtp_endpoint;
    }
    
    private void on_smtp_untrusted_host(Endpoint endpoint, Endpoint.SecurityType security,
        TlsConnection cx) {
        untrusted_host(endpoint, security, cx, Service.SMTP);
    }
    
    public Geary.Endpoint get_endpoint_for_service(Geary.Service service) {
        switch (service) {
            case Service.IMAP:
                return get_imap_endpoint();
            
            case Service.SMTP:
                return get_smtp_endpoint();
            
            default:
                assert_not_reached();
        }
    }
    
    private Geary.FolderPath? build_folder_path(Gee.List<string>? parts) {
        if (parts == null || parts.size == 0)
            return null;
        
        Geary.FolderPath path = new Imap.FolderRoot(parts[0]);
        for (int i = 1; i < parts.size; i++)
            path = path.get_child(parts.get(i));
        return path;
    }
    
    private string get_string_value(KeyFile key_file, string group, string key, string def = "") {
        try {
            return key_file.get_value(group, key);
        } catch(KeyFileError err) {
            // Ignore.
        }
        
        return def;
    }

    private string get_escaped_string(KeyFile key_file, string group, string key, string def = "") {
        try {
            return key_file.get_string(group, key);
        } catch (KeyFileError err) {
            // ignore
        }

        return def;
    }
    
    private Gee.List<string> get_string_list_value(KeyFile key_file, string group, string key) {
        try {
            string[] list = key_file.get_string_list(group, key);
            if (list.length > 0)
                return Geary.Collection.array_list_wrap<string>(list);
        } catch(KeyFileError err) {
            // Ignore.
        }
        
        return new Gee.ArrayList<string>();
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
        if (file == null || config_dir == null) {
            warning("Cannot save account, no file set.\n");
            return;
        }

        if (!config_dir.query_exists(cancellable)) {
            try {
                config_dir.make_directory_with_parents();
            } catch (Error err) {
                error("Error creating configuration directory for account '%s': %s",
                      this.id, err.message);
            }
        }

        if (!data_dir.query_exists(cancellable)) {
            try {
                data_dir.make_directory_with_parents();
            } catch (Error err) {
                error("Error creating storage directory for account '%s': %s",
                      this.id, err.message);
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

        key_file.set_value(GROUP, REAL_NAME_KEY, this.real_name);
        key_file.set_value(GROUP, NICKNAME_KEY, this.nickname);
        key_file.set_value(GROUP, PRIMARY_EMAIL_KEY, this.primary_mailbox.to_rfc822_string());
        key_file.set_value(GROUP, SERVICE_PROVIDER_KEY, this.service_provider.to_string());
        key_file.set_integer(GROUP, ORDINAL_KEY, this.ordinal);
        key_file.set_value(GROUP, IMAP_USERNAME_KEY, this.imap_credentials.user);
        key_file.set_boolean(GROUP, IMAP_REMEMBER_PASSWORD_KEY, this.imap_remember_password);
        if (smtp_credentials != null)
            key_file.set_value(GROUP, SMTP_USERNAME_KEY, this.smtp_credentials.user);
        key_file.set_boolean(GROUP, SMTP_REMEMBER_PASSWORD_KEY, this.smtp_remember_password);
        key_file.set_integer(GROUP, PREFETCH_PERIOD_DAYS_KEY, this.prefetch_period_days);
        key_file.set_boolean(GROUP, SAVE_SENT_MAIL_KEY, this.save_sent_mail);
        key_file.set_boolean(GROUP, USE_EMAIL_SIGNATURE_KEY, this.use_email_signature);
        key_file.set_string(GROUP, EMAIL_SIGNATURE_KEY, this.email_signature);
        if (alternate_mailboxes != null && this.alternate_mailboxes.size > 0) {
            string[] list = new string[this.alternate_mailboxes.size];
            for (int ctr = 0; ctr < this.alternate_mailboxes.size; ctr++)
                list[ctr] = this.alternate_mailboxes[ctr].to_rfc822_string();

            key_file.set_string_list(GROUP, ALTERNATE_EMAILS_KEY, list);
        }

        if (service_provider == ServiceProvider.OTHER) {
            key_file.set_value(GROUP, IMAP_HOST, this.default_imap_server_host);
            key_file.set_integer(GROUP, IMAP_PORT, this.default_imap_server_port);
            key_file.set_boolean(GROUP, IMAP_SSL, this.default_imap_server_ssl);
            key_file.set_boolean(GROUP, IMAP_STARTTLS, this.default_imap_server_starttls);

            key_file.set_value(GROUP, SMTP_HOST, this.default_smtp_server_host);
            key_file.set_integer(GROUP, SMTP_PORT, this.default_smtp_server_port);
            key_file.set_boolean(GROUP, SMTP_SSL, this.default_smtp_server_ssl);
            key_file.set_boolean(GROUP, SMTP_STARTTLS, this.default_smtp_server_starttls);
            key_file.set_boolean(GROUP, SMTP_USE_IMAP_CREDENTIALS, this.default_smtp_use_imap_credentials);
            key_file.set_boolean(GROUP, SMTP_NOAUTH, this.default_smtp_server_noauth);
        }

        key_file.set_string_list(GROUP, DRAFTS_FOLDER_KEY, (this.drafts_folder_path != null
            ? this.drafts_folder_path.as_list().to_array() : new string[] {}));
        key_file.set_string_list(GROUP, SENT_MAIL_FOLDER_KEY, (this.sent_mail_folder_path != null
            ? this.sent_mail_folder_path.as_list().to_array() : new string[] {}));
        key_file.set_string_list(GROUP, SPAM_FOLDER_KEY, (this.spam_folder_path != null
            ? this.spam_folder_path.as_list().to_array() : new string[] {}));
        key_file.set_string_list(GROUP, TRASH_FOLDER_KEY, (this.trash_folder_path != null
            ? this.trash_folder_path.as_list().to_array() : new string[] {}));
        key_file.set_string_list(GROUP, ARCHIVE_FOLDER_KEY, (this.archive_folder_path != null
            ? this.archive_folder_path.as_list().to_array() : new string[] {}));

        key_file.set_boolean(GROUP, SAVE_DRAFTS_KEY, this.save_drafts);

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
    
    public async void clear_stored_passwords_async(ServiceFlag services) throws Error {
        Error? return_error = null;
        check_mediator_instance();
        CredentialsMediator mediator = Geary.Engine.instance.authentication_mediator;
        
        try {
            if (services.has_imap())
                yield mediator.clear_password_async(Service.IMAP, this);
        } catch (Error e) {
            return_error = e;
        }
        
        try {
            if (services.has_smtp() && smtp_credentials != null)
                yield mediator.clear_password_async(Service.SMTP, this);
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
        if (data_dir == null) {
            warning("Cannot remove account storage directory; nothing to remove");
        } else {
            yield Files.recursive_delete_async(data_dir, cancellable);
        }

        if (config_dir == null) {
            warning("Cannot remove account configuration directory; nothing to remove");
        } else {
            yield Files.recursive_delete_async(config_dir, cancellable);
        }
        
        try {
            yield clear_stored_passwords_async(ServiceFlag.IMAP | ServiceFlag.SMTP);
        } catch (Error e) {
            debug("Error clearing SMTP password: %s", e.message);
        }
    }

    /**
     * Determines if this account contains a specific email address.
     *
     * Returns true if the address part of `email` is equal to (case
     * insensitive) the address part of this account's primary mailbox
     * or any of its secondary mailboxes.
     */
    public bool has_email_address(Geary.RFC822.MailboxAddress email) {
        return (
            this.primary_mailbox.equal_to(email) ||
            (this.alternate_mailboxes != null &&
             this.alternate_mailboxes.fold<bool>((alt) => {
                     return alt.equal_to(email);
                 }, false))
        );
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
