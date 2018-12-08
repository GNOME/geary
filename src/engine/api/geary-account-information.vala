/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
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

    /**
     * A human-readable label describing the email service provider.
     *
     * Known providers such as Gmail will have a label specified by
     * clients, but other accounts can only really be identified by
     * their server names. This attempts to extract a 'nice' value for
     * label based on the service's host names.
     */
    public string service_label {
        owned get {
            string? value = this._service_label;
            if (value == null) {
                string[] host_parts = this.imap.host.split(".");
                if (host_parts.length > 1) {
                    host_parts = host_parts[1:host_parts.length];
                }
                // don't stash this in _service_label since we want it
                // updated if the service host names change
                value = string.joinv(".", host_parts);
            }
            return value;
        }
        set { this._service_label = value; }
    }
    private string? _service_label = null;

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
     * The default sender mailbox address for the account.
     *
     * This is the first mailbox in the {@link sender_mailboxes} list.
     */
    public Geary.RFC822.MailboxAddress primary_mailbox {
        owned get { return this.sender_mailboxes.get(0); }
    }

    /**
     * A read-only list of sender mailbox address for the account.
     *
     * The first address in the list is the default address, others
     * are essentially aliases.
     */
    public Gee.List<Geary.RFC822.MailboxAddress>? sender_mailboxes {
        owned get { return this.mailboxes.read_only_view; }
    }

    /** Determines if the account has more than one sender mailbox. */
    public bool has_sender_aliases {
        get { return this.sender_mailboxes.size > 1; }
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

    /**
     * The source of authentication credentials for this account.
     */
    public CredentialsMediator mediator { get; private set; }

    /* Incoming email service configuration. */
    public ServiceInformation imap {
        get; set;
        default = new ServiceInformation(Protocol.IMAP);
    }

    /* Outgoing email service configuration. */
    public ServiceInformation smtp {
        get; set;
        default = new ServiceInformation(Protocol.SMTP);
    }

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

    private Gee.List<Geary.RFC822.MailboxAddress> mailboxes {
        get; private set;
        default = new Gee.LinkedList<Geary.RFC822.MailboxAddress>();
    }

    private bool _save_sent_mail = true;


    /**
     * Emitted when a service has reported TLS certificate warnings.
     *
     * It is up to the caller to pin the certificate appropriately if
     * the user does not want to receive these warnings in the future.
     */
    public signal void untrusted_host(ServiceInformation service,
                                      TlsNegotiationMethod method,
                                      GLib.TlsConnection cx);

    /** Indicates that properties contained herein have changed. */
    public signal void information_changed();

    /**
     * Creates a new account with default settings.
     */
    public AccountInformation(string id,
                              ServiceProvider provider,
                              CredentialsMediator mediator,
                              RFC822.MailboxAddress primary_mailbox) {
        this.id = id;
        this.mediator = mediator;
        this.service_provider = provider;
        append_sender(primary_mailbox);
    }

    /**
     * Creates a copy of an existing config.
     */
    public AccountInformation.copy(AccountInformation other) {
        this(
            other.id,
            other.service_provider,
            other.mediator,
            other.primary_mailbox
        );
        this.service_label = other.service_label;
        this.nickname = other.nickname;
        if (other.mailboxes.size > 1) {
            this.mailboxes.add_all(
                other.mailboxes.slice(1, other.mailboxes.size)
            );
        }
        this.prefetch_period_days = other.prefetch_period_days;
        this.save_sent_mail = other.save_sent_mail;
        this.use_email_signature = other.use_email_signature;
        this.email_signature = other.email_signature;
        this.save_drafts = other.save_drafts;

        this.imap = new ServiceInformation.copy(other.imap);
        this.smtp = new ServiceInformation.copy(other.smtp);

        this.drafts_folder_path = other.drafts_folder_path;
        this.sent_mail_folder_path = other.sent_mail_folder_path;
        this.spam_folder_path = other.spam_folder_path;
        this.trash_folder_path = other.trash_folder_path;
        this.archive_folder_path = other.archive_folder_path;

        this.config_dir = other.config_dir;
        this.data_dir = other.data_dir;
    }

    /** Sets the location of the account's storage directories. */
    public void set_account_directories(GLib.File config, GLib.File data) {
        this.config_dir = config;
        this.data_dir = data;
    }

    /**
     * Determines if a mailbox is in the sender mailbox list.
     *
     * Returns true if the given address is equal to one of the
     * addresses in {@link sender_mailboxes}, by case-insensitive
     * matching the address parts.
     *
     * @see Geary.RFC822.MailboxAddress.equal_to
     */
    public bool has_sender_mailbox(Geary.RFC822.MailboxAddress email) {
        return this.mailboxes.any_match((alt) => alt.equal_to(email));
    }

    /**
     * Appends a mailbox to the list of sender mailboxes.
     *
     * Mailboxes with duplicate addresses will not be added.
     *
     * Returns true if the mailbox was appended.
     */
    public bool append_sender(Geary.RFC822.MailboxAddress mailbox) {
        bool add = !has_sender_mailbox(mailbox);
        if (add) {
            this.mailboxes.add(mailbox);
        }
        return add;
    }

    /**
     * Inserts a mailbox into the list of sender mailboxes.
     *
     * Mailboxes with duplicate addresses will not be added.
     *
     * Returns true if the mailbox was inserted.
     */
    public bool insert_sender(int index, Geary.RFC822.MailboxAddress mailbox) {
        bool add = !has_sender_mailbox(mailbox);
        if (add) {
            this.mailboxes.insert(index, mailbox);
        }
        return add;
    }

    /**
     * Removes a mailbox from the list of sender mailboxes.
     *
     * The last mailbox cannot be removed.
     *
     * Returns true if the mailbox was removed.
     */
    public bool remove_sender(Geary.RFC822.MailboxAddress mailbox) {
        bool removed = false;
        if (this.mailboxes.size > 1) {
            removed = this.mailboxes.remove(mailbox);
        }
        return removed;
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
        switch (this.smtp.smtp_credentials_source) {
        case IMAP:
            smtp = this.imap.credentials;
            break;
        case CUSTOM:
            smtp = this.smtp.credentials;
            break;
        }
        return smtp;
    }

    /**
     * Loads this account's SMTP credentials from the mediator, if needed.
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
            loaded = yield this.mediator.load_token(
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
        return yield this.mediator.prompt_token(
            this, this.smtp, cancellable
        );
    }

    /**
     * Loads this account's IMAP credentials from the mediator, if needed.
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
            loaded = yield this.mediator.load_token(
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
        return yield this.mediator.prompt_token(
            this, this.imap, cancellable
        );
    }

    public static Geary.FolderPath? build_folder_path(Gee.List<string>? parts) {
        if (parts == null || parts.size == 0)
            return null;
        
        Geary.FolderPath path = new Imap.FolderRoot(parts[0]);
        for (int i = 1; i < parts.size; i++)
            path = path.get_child(parts.get(i));
        return path;
    }

    public bool equal_to(AccountInformation other) {
        return (
            this == other || (
                // This is probably overkill, but handy for testing.
                this.id == other.id &&
                this.ordinal == other.ordinal &&
                this.mediator == other.mediator &&
                this.service_provider == other.service_provider &&
                this.service_label == other.service_label &&
                this.nickname == other.nickname &&
                this.primary_mailbox.equal_to(other.primary_mailbox) &&
                this.has_sender_aliases == other.has_sender_aliases &&
                this.sender_mailboxes.size == other.sender_mailboxes.size &&
                traverse(this.sender_mailboxes).all(
                    addr => other.sender_mailboxes.contains(addr)
                ) &&
                this.prefetch_period_days == other.prefetch_period_days &&
                this.save_sent_mail == other.save_sent_mail &&
                this.imap.equal_to(other.imap) &&
                this.smtp.equal_to(other.smtp) &&
                this.use_email_signature == other.use_email_signature &&
                this.email_signature == other.email_signature &&
                this.save_drafts == other.save_drafts &&
                this.drafts_folder_path == other.drafts_folder_path &&
                this.sent_mail_folder_path == other.sent_mail_folder_path &&
                this.spam_folder_path == other.spam_folder_path &&
                this.trash_folder_path == other.trash_folder_path &&
                this.archive_folder_path == other.archive_folder_path &&
                this.config_dir == other.config_dir &&
                this.data_dir == other.data_dir
            )
        );
    }

}
