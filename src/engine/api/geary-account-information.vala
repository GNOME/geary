/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class Geary.AccountInformation : BaseObject {

    /** Name of of the nickname property, for signal handlers. */
    public const string PROP_NICKNAME = "nickname";

    public const int DEFAULT_PREFETCH_PERIOD_DAYS = 14;

    public const string SETTINGS_FILENAME = "geary.ini";


    public static int next_ordinal = 0;


    /** Comparator for account info objects based on their ordinals. */
    public static int compare_ascending(AccountInformation a, AccountInformation b) {
        int diff = a.ordinal - b.ordinal;
        if (diff != 0)
            return diff;

        // Stabilize on nickname, which should always be unique.
        return a.display_name.collate(b.display_name);
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

    /** Specifies the email provider for this account. */
    public Geary.ServiceProvider service_provider { get; private set; }

    /** A human-readable label describing the email service provider. */
    public string service_label {
        get; public set;
    }

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
                                      TlsNegotiationMethod method,
                                      GLib.TlsConnection cx);

    /** Indicates that properties contained herein have changed. */
    public signal void information_changed();

    /**
     * Creates a new, empty account info file.
     */
    public AccountInformation(string id,
                              ServiceProvider provider,
                              ServiceInformation imap,
                              ServiceInformation smtp) {
        this.id = id;
        this.service_provider = provider;
        this.imap = imap;
        this.smtp = smtp;

        // Known providers such as Gmail will have a label specified
        // by clients, but other accounts can only really be
        // identified by their server names. Try to extract a 'nice'
        // value for label based on service host names.
        string imap_host = imap.host;
        string[] host_parts = imap_host.split(".");
        if (host_parts.length > 1) {
            host_parts = host_parts[1:host_parts.length];
        }
        this.service_label = string.joinv(".", host_parts);
    }

    /**
     * Creates a copy of an instance.
     */
    public AccountInformation.temp_copy(AccountInformation from) {
        this(
            from.id,
            from.service_provider,
            from.imap.temp_copy(),
            from.smtp.temp_copy()
        );
        copy_from(from);
        this.is_copy = true;
    }

    ~AccountInformation() {
        disconnect_service_endpoints();
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
     * Return a read only, ordered list of the account's sender mailboxes.
     */
    public Gee.List<Geary.RFC822.MailboxAddress> get_sender_mailboxes() {
        Gee.List<RFC822.MailboxAddress> all =
            new Gee.LinkedList<RFC822.MailboxAddress>();

        all.add(this.primary_mailbox);
        if (alternate_mailboxes != null) {
            all.add_all(alternate_mailboxes);
        }

        return all.read_only_view;
    }

    /**
     * Appends a sender mailbox to the account.
     */
    public void append_sender_mailbox(Geary.RFC822.MailboxAddress mailbox) {
        if (this.primary_mailbox == null) {
            this.primary_mailbox = mailbox;
        } else {
            if (this.alternate_mailboxes == null) {
                this.alternate_mailboxes =
                    new Gee.LinkedList<Geary.RFC822.MailboxAddress>();
            }
            this.alternate_mailboxes.add(mailbox);
        }
    }

    /**
     * Appends a sender mailbox to the account.
     */
    public void insert_sender_mailbox(int index,
                                      Geary.RFC822.MailboxAddress mailbox) {
        Geary.RFC822.MailboxAddress? alt_insertion = null;
        int actual_index = index;
        if (actual_index == 0) {
            if (this.primary_mailbox == null) {
                this.primary_mailbox = mailbox;
            } else {
                this.primary_mailbox = mailbox;
                alt_insertion = this.primary_mailbox;
                actual_index = 0;
            }
        } else {
            alt_insertion = mailbox;
            actual_index--;
        }

        if (alt_insertion != null) {
            if (this.alternate_mailboxes == null) {
                this.alternate_mailboxes =
                    new Gee.LinkedList<Geary.RFC822.MailboxAddress>();
            }
            this.alternate_mailboxes.insert(actual_index, alt_insertion);
        }
    }

    /**
     * Removes a sender mailbox for the account.
     */
    public void remove_sender_mailbox(Geary.RFC822.MailboxAddress mailbox) {
        if (this.primary_mailbox == mailbox) {
            this.primary_mailbox = (
                this.alternate_mailboxes != null &&
                !this.alternate_mailboxes.is_empty
            ) ? this.alternate_mailboxes.remove_at(0) : null;
        } else if (this.alternate_mailboxes != null) {
            this.alternate_mailboxes.remove_at(
                this.alternate_mailboxes.index_of(mailbox)
            );
        }
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
             this.alternate_mailboxes.any_match((alt) => {
                     return alt.equal_to(email);
                 }))
        );
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
     * Loads this account's SMTP credentials from its mediator, if needed.
     *
     * This method may cause the user to be prompted for their
     * secrets, thus it may yield for some time.
     *
     * Returns true if the credentials were successfully loaded or had
     * been previously loaded, the credentials could not be loaded and
     * the SMTP credentials are invalid.
     */
    public async bool load_smtp_credentials(GLib.Cancellable? cancellable)
        throws GLib.Error {
        Credentials? creds = get_smtp_credentials();
        bool loaded = (creds == null || creds.is_complete());
        if (!loaded && creds != null) {
            ServiceInformation service = this.smtp;
            if (this.smtp.smtp_use_imap_credentials) {
                service = this.imap;
            }
            loaded = yield service.mediator.load_token(
                this, service, cancellable
            );
        }
        return loaded;
    }

    /**
     * Prompts the user for their SMTP authentication secret.
     *
     * Returns true if the credentials were successfully entered, else
     * false if the user dismissed the prompt.
     */
    public async bool prompt_smtp_credentials(GLib.Cancellable? cancellable)
        throws GLib.Error {
        return yield this.smtp.mediator.prompt_token(
            this, this.smtp, cancellable
        );
    }

    /**
     * Loads this account's IMAP credentials from its mediator, if needed.
     *
     * This method may cause the user to be prompted for their
     * secrets, thus it may yield for some time.
     *
     * Returns true if the credentials were successfully loaded or had
     * been previously loaded, the credentials could not be loaded and
     * the IMAP credentials are invalid.
     */
    public async bool load_imap_credentials(GLib.Cancellable? cancellable)
        throws GLib.Error {
        Credentials? creds = this.imap.credentials;
        bool loaded = creds.is_complete();
        if (!loaded) {
            loaded = yield this.imap.mediator.load_token(
                this, this.imap, cancellable
            );
        }
        return loaded;
    }

    /**
     * Prompts the user for their IMAP authentication secret.
     *
     * Returns true if the credentials were successfully entered, else
     * false if the user dismissed the prompt.
     */
    public async bool prompt_imap_credentials(GLib.Cancellable? cancellable)
        throws GLib.Error {
        return yield this.imap.mediator.prompt_token(
            this, this.imap, cancellable
        );
    }

    internal void connect_imap_service(Endpoint service) {
        if (this.imap.endpoint == null) {
            this.imap.endpoint = service;
            this.imap.endpoint.untrusted_host.connect(
                on_imap_untrusted_host
            );
        }
    }

    internal void connect_smtp_service(Endpoint service) {
        if (this.smtp.endpoint == null) {
            this.smtp.endpoint = service;
            this.smtp.endpoint.untrusted_host.connect(
                on_smtp_untrusted_host
            );
        }
    }

    internal void disconnect_service_endpoints() {
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

    public static Geary.FolderPath? build_folder_path(Gee.List<string>? parts) {
        if (parts == null || parts.size == 0)
            return null;
        
        Geary.FolderPath path = new Imap.FolderRoot(parts[0]);
        for (int i = 1; i < parts.size; i++)
            path = path.get_child(parts.get(i));
        return path;
    }

    private void on_imap_untrusted_host(TlsNegotiationMethod method,
                                        GLib.TlsConnection cx) {
        untrusted_host(this.imap, method, cx);
    }

    private void on_smtp_untrusted_host(TlsNegotiationMethod method,
                                        GLib.TlsConnection cx) {
        untrusted_host(this.smtp, method, cx);
    }

}
