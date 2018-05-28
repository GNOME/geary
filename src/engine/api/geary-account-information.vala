/*
 * Copyright 2016 Software Freedom Conservancy Inc.
n *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class Geary.AccountInformation : BaseObject {

    /** Name of of the nickname property, for signal handlers. */
    public const string PROP_NICKNAME = "nickname";

    public const int DEFAULT_PREFETCH_PERIOD_DAYS = 14;

    public const string SETTINGS_FILENAME = "geary.ini";


    public static int next_ordinal = 0;


    private static Gee.HashMap<string,weak Endpoint> known_endpoints =
        new Gee.HashMap<string,weak Endpoint>();


    /** Comparator for account info objects based on their ordinals. */
    public static int compare_ascending(AccountInformation a, AccountInformation b) {
        int diff = a.ordinal - b.ordinal;
        if (diff != 0)
            return diff;

        // Stabilize on nickname, which should always be unique.
        return a.display_name.collate(b.display_name);
    }

    private static Geary.Endpoint get_shared_endpoint(ServiceInformation service,
                                                      Endpoint endpoint) {
        string key = "%s/%s:%u".printf(
            service.protocol.user_label(),
            endpoint.remote_address.hostname,
            endpoint.remote_address.port
        );

        weak Endpoint? cached = AccountInformation.known_endpoints.get(key);
        weak Endpoint? shared = endpoint;
        if (cached != null) {
            shared = cached;
            AccountInformation.known_endpoints.set(key, shared);
        }

        return shared;
    }


    /** Location of the account information's settings key file. */
    public File? settings_file {
        owned get {
            File? settings = null;
            if (this.config_dir != null) {
                settings = this.config_dir.get_child(SETTINGS_FILENAME);
            }
            return settings;
        }
    }

    /**
     * Location of the account's config directory.
     *
     * This directory is used to store small, per-account
     * configuration files, including the account's settings key file.
     */
    public File? config_dir { get; private set; default = null; }

    /**
     * Location of the account's data directory.
     *
     * This directory is used to store large, per-account data files
     * such as the account database.
     */
    public File? data_dir { get; private set; default = null; }

    //
    // IMPORTANT: When adding new properties, be sure to add them to the copy method.
    //

    /**
     * A unique, immutable, machine-readable identifier for this account.
     *
     * This string's value should be treated as an opaque, private
     * implementation detail and not parsed at all. For older accounts
     * it will be an email address, for newer accounts it will be
     * something else. Once created, this string will never change.
     */
    public string id { get; private set; }

    /**
     * A unique human-readable display name for this account.
     *
     * Use this to display a string to the user that can uniquely
     * identify this account. Note this value is mutable - it may
     * change as a result of user action, so do not rely on it staying
     * the same.
     */
    public string display_name {
        get {
            return (!String.is_empty_or_whitespace(this.nickname))
                ? this.nickname
                : this.primary_mailbox.address;
        }
    }

    /**
     * User-provided label for the account.
     *
     * This is not to be used in the UI (use `display_name` instead)
     * and not transmitted on the wire or used in correspondence.
     */
    public string nickname { get; set; default = ""; }

    /**
     * The default email address for the account.
     */
    public Geary.RFC822.MailboxAddress primary_mailbox {
        get; set; default = new RFC822.MailboxAddress("", "");
    }

    /**
     * A list of additional email addresses this account accepts.
     *
     * Use {@link add_alternate_mailbox} or {@link replace_alternate_mailboxes} rather than edit
     * this collection directly.
     *
     * @see get_all_mailboxes
     */
    public Gee.List<Geary.RFC822.MailboxAddress>? alternate_mailboxes { get; private set; default = null; }

    public Geary.ServiceProvider service_provider {
        get; set; default = Geary.ServiceProvider.OTHER;
    }
    public int prefetch_period_days {
        get; set; default = DEFAULT_PREFETCH_PERIOD_DAYS;
    }

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
    public int ordinal {
        get; set; default = AccountInformation.next_ordinal++;
    }

    /* Information related to the account's server-side authentication
     * and configuration. */
    public ServiceInformation imap { get; private set; }
    public ServiceInformation smtp { get; private set; }

    /** A lock that can be used to ensure saving is serialised. */
    public Nonblocking.Mutex write_lock {
        get; private set; default = new Nonblocking.Mutex();
    }

    // These properties are only used if the service provider's
    // account type does not override them.

    public bool use_email_signature { get; set; default = false; }
    public string email_signature { get; set; default = ""; }

    public Geary.FolderPath? drafts_folder_path { get; set; default = null; }
    public Geary.FolderPath? sent_mail_folder_path { get; set; default = null; }
    public Geary.FolderPath? spam_folder_path { get; set; default = null; }
    public Geary.FolderPath? trash_folder_path { get; set; default = null; }
    public Geary.FolderPath? archive_folder_path { get; set; default = null; }

    public bool save_drafts { get; set; default = true; }

    public bool is_copy { get; set; default = false; }

    private bool _save_sent_mail = true;


    /**
     * Indicates the supplied {@link Endpoint} has reported TLS certificate warnings during
     * connection.
     *
     * Since this {@link Endpoint} persists for the lifetime of the {@link AccountInformation},
     * marking it as trusted once will survive the application session.  It is up to the caller to
     * pin the certificate appropriately if the user does not want to receive these warnings in
     * the future.
     */
    public signal void untrusted_host(ServiceInformation service,
                                      Endpoint.SecurityType security,
                                      TlsConnection cx);

    /** Indicates that properties contained herein have changed. */
    public signal void information_changed();

    /**
     * Creates a new, empty account info file.
     */
    public AccountInformation(string id,
                              ServiceInformation imap,
                              ServiceInformation smtp) {
        this.id = id;
        this.imap = imap;
        this.smtp = smtp;
    }

    /**
     * Creates a copy of an instance.
     */
    public AccountInformation.temp_copy(AccountInformation from) {
        this(from.id, from.imap.temp_copy(), from.smtp.temp_copy());
        copy_from(from);
        this.is_copy = true;
    }

    ~AccountInformation() {
        disconnect_endpoints();
    }


    /** Copies all properties from an instance into this one. */
    public void copy_from(AccountInformation from) {
        this.id = from.id;
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
        this.imap.copy_from(from.imap);
        this.smtp.copy_from(from.smtp);
        this.drafts_folder_path = from.drafts_folder_path;
        this.sent_mail_folder_path = from.sent_mail_folder_path;
        this.spam_folder_path = from.spam_folder_path;
        this.trash_folder_path = from.trash_folder_path;
        this.archive_folder_path = from.archive_folder_path;
        this.save_drafts = from.save_drafts;
        this.use_email_signature = from.use_email_signature;
        this.email_signature = from.email_signature;
    }

    /** Sets the location of the account's storage directories. */
    public void set_account_directories(GLib.File config, GLib.File data) {
        this.config_dir = config;
        this.data_dir = data;
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
     * Only the DRAFTS, SENT, SPAM, TRASH and ARCHIVE special folder types are
     * valid to pass to this function.
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

        // This account's information should be stored again. Signal this.
        information_changed();
    }

    /**
     * Returns the best credentials to use for SMTP authentication.
     *
     * This method checks for SMTP services that use IMAP credentials
     * for authentication and if enabled, returns those. If this
     * method returns null, then SMTP authentication should not be
     * attempted for this account.
     */
    public Credentials? get_smtp_credentials() {
        Credentials? smtp = null;
        if (!this.smtp.smtp_noauth) {
            smtp = this.smtp.smtp_use_imap_credentials
                ? this.imap.credentials
                : this.smtp.credentials;
        }
        return smtp;
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
                if (this.imap.credentials != null)
                    this.imap.credentials =
                        this.imap.credentials.copy_with_password(null);
            } else if (services.has_smtp()) {
                if (this.smtp.credentials != null)
                    this.smtp.credentials =
                        this.smtp.credentials.copy_with_password(null);
            }
        }
        
        // Only call get_passwords on anything that hasn't been set
        // (incorrectly) previously.
        ServiceFlag get_services = 0;
        if (services.has_imap() && !this.imap.credentials.is_complete())
            get_services |= ServiceFlag.IMAP;
        
        if (services.has_smtp() && this.smtp.credentials != null && !this.smtp.credentials.is_complete())
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
        if (this.imap.mediator == null || this.smtp.mediator == null)
            throw new EngineError.OPEN_REQUIRED(
                "Account %s needs to be open with valid Geary.CredentialsMediators".printf(this.id));
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

        ServiceFlag failed_services = 0;

        if (services.has_imap()) {
            string? imap_password = yield this.imap.mediator.get_password_async(
                this.imap
            );

            if (imap_password != null)
                this.imap.set_password(imap_password, this.imap.remember_password);
             else
                failed_services |= ServiceFlag.IMAP;
        }

        if (services.has_smtp() && this.smtp.credentials != null) {
            string? smtp_password = yield this.smtp.mediator.get_password_async(
                this.smtp
            );

            if (smtp_password != null)
                this.smtp.set_password(smtp_password, this.smtp.remember_password);
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

        if (this.smtp.credentials == null)
            services &= ~ServiceFlag.SMTP;

        if (!yield this.imap.mediator.prompt_passwords_async(
            services, this, out imap_password, out smtp_password,
            out imap_remember_password, out smtp_remember_password))
            return false;

        if (services.has_imap()) {
            imap.set_password(imap_password, imap_remember_password);
        }

        if (services.has_smtp()) {
            smtp.set_password(smtp_password, smtp_remember_password);
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


        if (services.has_imap()) {
            if (this.imap.remember_password)
                yield this.imap.mediator.set_password_async(this.imap);
            else
                yield this.imap.mediator.clear_password_async(this.imap);
        }

        if (services.has_smtp() && this.smtp.credentials != null) {
            if (this.smtp.remember_password)
                yield this.smtp.mediator.set_password_async(this.smtp);
            else
                yield this.smtp.mediator.clear_password_async(this.smtp);
        }
    }

    public async void clear_stored_passwords_async(ServiceFlag services) throws Error {
        Error? return_error = null;
        check_mediator_instance();

        try {
            if (services.has_imap())
                yield this.imap.mediator.clear_password_async(this.imap);
        } catch (Error e) {
            return_error = e;
        }

        try {
            if (services.has_smtp() && this.smtp.credentials != null)
                yield this.smtp.mediator.clear_password_async(this.smtp);
        } catch (Error e) {
            return_error = e;
        }

        if (return_error != null)
            throw return_error;
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

    internal void connect_endpoints() {
        if (this.imap.endpoint == null) {
            this.imap.endpoint = get_imap_endpoint();
            this.imap.endpoint.untrusted_host.connect(
                on_imap_untrusted_host
            );
        }
        if (this.smtp.endpoint == null) {
            this.smtp.endpoint = get_smtp_endpoint();
            this.smtp.endpoint.untrusted_host.connect(
                on_smtp_untrusted_host
            );
        }
    }

    internal void disconnect_endpoints() {
        if (this.imap.endpoint != null) {
            this.imap.endpoint.untrusted_host.disconnect(
                on_imap_untrusted_host
            );
            this.imap.endpoint = null;
        }
        if (this.smtp.endpoint != null) {
            this.smtp.endpoint.untrusted_host.disconnect(
                on_smtp_untrusted_host
            );
            this.smtp.endpoint = null;
        }
    }

    private Endpoint get_imap_endpoint() {
        Endpoint? imap_endpoint = null;
        switch (this.service_provider) {
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
                if (this.imap.use_ssl)
                    imap_flags |= Endpoint.Flags.SSL;
                if (this.imap.use_starttls)
                    imap_flags |= Endpoint.Flags.STARTTLS;

                imap_endpoint = new Endpoint(this.imap.host, this.imap.port,
                    imap_flags, Imap.ClientConnection.RECOMMENDED_TIMEOUT_SEC);
            break;
            
            default:
                assert_not_reached();
        }

        // look for existing one in the global pool; want to use that
        // because Endpoint is mutable and signalled in such a way
        // that it's better to share them
        imap_endpoint = get_shared_endpoint(this.imap, imap_endpoint);

        // bind shared Endpoint signal to this AccountInformation's signal
        imap_endpoint.untrusted_host.connect(on_imap_untrusted_host);

        return imap_endpoint;
    }

    private Endpoint get_smtp_endpoint() {
        Endpoint? smtp_endpoint = null;
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
                if (this.smtp.use_ssl)
                    smtp_flags |= Endpoint.Flags.SSL;
                if (this.smtp.use_starttls)
                    smtp_flags |= Endpoint.Flags.STARTTLS;

                smtp_endpoint = new Endpoint(this.smtp.host, this.smtp.port,
                    smtp_flags, Smtp.ClientConnection.DEFAULT_TIMEOUT_SEC);
            break;

            default:
                assert_not_reached();
        }

        // look for existing one in the global pool; want to use that
        // because Endpoint is mutable and signalled in such a way
        // that it's better to share them
        smtp_endpoint = get_shared_endpoint(this.smtp, smtp_endpoint);

        // bind shared Endpoint signal to this AccountInformation's signal
        smtp_endpoint.untrusted_host.connect(on_smtp_untrusted_host);

        return smtp_endpoint;
    }

    public static Geary.FolderPath? build_folder_path(Gee.List<string>? parts) {
        if (parts == null || parts.size == 0)
            return null;
        
        Geary.FolderPath path = new Imap.FolderRoot(parts[0]);
        for (int i = 1; i < parts.size; i++)
            path = path.get_child(parts.get(i));
        return path;
    }

    private void on_imap_untrusted_host(Endpoint.SecurityType security,
                                        TlsConnection cx) {
        untrusted_host(this.imap, security, cx);
    }

    private void on_smtp_untrusted_host(Endpoint.SecurityType security,
                                        TlsConnection cx) {
        untrusted_host(this.smtp, security, cx);
    }

}
