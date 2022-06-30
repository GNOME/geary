/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

public class Geary.AccountInformation : BaseObject {


    public const int DEFAULT_PREFETCH_PERIOD_DAYS = 14;


    /** The next ordinal that should be allocated for an account. */
    public static int next_ordinal = 0;

    /** Comparator for account info objects based on their ordinals. */
    public static int compare_ascending(AccountInformation a, AccountInformation b) {
        int diff = a.ordinal - b.ordinal;
        if (diff != 0)
            return diff;

        // Stabilize on display name, which should always be unique.
        return a.display_name.collate(b.display_name);
    }


    /** A unique (engine-wide), opaque identifier for the account. */
    public string id { get; private set; }

    /** A unique (engine-wide) ordering for the account. */
    public int ordinal {
        get; set; default = AccountInformation.next_ordinal++;
    }

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
                string email_domain = this.primary_mailbox.domain;
                if (this.incoming.host.has_suffix(email_domain)) {
                    value = email_domain;
                } else {
                    string[] host_parts = this.incoming.host.split(".");
                    // If first part is an integer, looks like an ip so ignore it
                    if (host_parts.length > 2 && int.parse(host_parts[0]) == 0) {
                        host_parts = host_parts[1:host_parts.length];
                    }
                    value = string.joinv(".", host_parts);
                }
                // Don't stash the calculated value in _service_label
                // since we want it updated if the service host names
                // change
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
            return (!String.is_empty_or_whitespace(this.label))
                ? this.label
                : this.primary_mailbox.address;
        }
    }

    /**
     * User-provided label for the account.
     *
     * This is not to be used in the UI (use `display_name` instead)
     * and not transmitted on the wire or used in correspondence.
     */
    public string label { get; set; default = ""; }

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

    /** Specifies the number of days to be fetched by the account sync. */
    public int prefetch_period_days {
        get; set; default = DEFAULT_PREFETCH_PERIOD_DAYS;
    }

    /** Specifies if sent email should be saved to the Sent folder. */
    public bool save_sent {
        get {
            bool save = _save_sent;
            switch (this.service_provider) {
            case GMAIL:
            case OUTLOOK:
                save = false;
                break;
            default:
                break;
            }
            return save;
        }
        set { this._save_sent = value; }
    }
    private bool _save_sent = true;

    /** Determines if drafts should be saved on the server. */
    public bool save_drafts { get; set; default = true; }

    /**
     * The source of authentication credentials for this account.
     */
    public CredentialsMediator mediator { get; private set; }

    /* Incoming email service configuration. */
    public ServiceInformation incoming { get; set; }

    /* Outgoing email service configuration. */
    public ServiceInformation outgoing { get; set; }

    /** A lock that can be used to ensure saving is serialised. */
    public Nonblocking.Mutex write_lock {
        get; private set; default = new Nonblocking.Mutex();
    }

    /** Specifies if an email sig should be appended to new messages. */
    public bool use_signature { get; set; default = false; }

    /** Specifies the email sig to be appended to new messages. */
    public string signature { get; set; default = ""; }

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

    private Gee.Map<Folder.SpecialUse?,Gee.List<string>> special_use_paths =
        new Gee.HashMap<Folder.SpecialUse?,Gee.List<string>>(
            (k) => GLib.int_hash(k),
            (k1, k2) => (Folder.SpecialUse) k1 == (Folder.SpecialUse) k2
        );

    private Gee.List<Geary.RFC822.MailboxAddress> mailboxes {
        get; private set;
        default = new Gee.LinkedList<Geary.RFC822.MailboxAddress>();
    }


    /**
     * Emitted when a service has reported an authentication failure.
     *
     * No further connection attempts will be made after this signal
     * has been fired until the associated {@link ClientService} has
     * been restarted. It is up to the client to prompt the user for
     * updated credentials and restart the service.
     */
    public signal void authentication_failure(ServiceInformation service);

    /**
     * Emitted when an endpoint has reported TLS certificate warnings.
     *
     * This signal is emitted when either of the incoming or outgoing
     * endpoints emit the signal with the same name. It may be more
     * convenient for clients to connect to this instead.
     *
     * No further connection attempts will be made after this signal
     * has been fired until the associated {@link ClientService} has
     * been restarted. It is up to the client to prompt the user to
     * take action about the certificate (e.g. decide to pin it) then
     * restart the service.
     *
     * @see Endpoint.untrusted_host
     */
    public signal void untrusted_host(ServiceInformation service,
                                      Endpoint endpoint,
                                      GLib.TlsConnection cx);

    /** Emitted when the account settings have changed. */
    public signal void changed();

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
        this.incoming = new ServiceInformation(Protocol.IMAP, provider);
        this.outgoing = new ServiceInformation(Protocol.SMTP, provider);

        provider.set_account_defaults(this);

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
        this.label = other.label;
        if (other.mailboxes.size > 1) {
            this.mailboxes.add_all(
                other.mailboxes.slice(1, other.mailboxes.size)
            );
        }
        this.prefetch_period_days = other.prefetch_period_days;
        this.save_sent = other.save_sent;
        this.save_drafts = other.save_drafts;
        this.use_signature = other.use_signature;
        this.signature = other.signature;

        this.incoming = new ServiceInformation.copy(other.incoming);
        this.outgoing = new ServiceInformation.copy(other.outgoing);

        this.special_use_paths.set_all(other.special_use_paths);

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
     * Replace a mailbox at the specified index.
     */
    public void replace_sender(int index, Geary.RFC822.MailboxAddress mailbox) {
        this.mailboxes.set(index, mailbox);
    }

    /**
     * Returns the folder path steps configured for a specific use.
     */
    public Gee.List<string> get_folder_steps_for_use(Folder.SpecialUse use) {
        var steps = this.special_use_paths.get(use);
        if (steps != null) {
            steps = steps.read_only_view;
        } else {
            steps = Gee.List.empty();
        }
        return steps;
    }

    /**
     * Sets the configured folder path steps for a specific use.
     */
    public void set_folder_steps_for_use(Folder.SpecialUse special,
                                         Gee.List<string>? new_path) {
        var existing = this.special_use_paths.get(special);
        if (new_path != null && !new_path.is_empty) {
            this.special_use_paths.set(special, new_path);
        } else {
            this.special_use_paths.unset(special);
        }
        if ((existing == null && new_path != null) ||
            (existing != null && new_path == null) ||
            (existing != null &&
             (existing.size != new_path.size ||
              existing.contains_all(new_path)))) {
            changed();
        }
    }

    /**
     * Returns a folder path based on the configured steps for a use.
     */
    public FolderPath? new_folder_path_for_use(FolderRoot root,
                                               Folder.SpecialUse use) {
        FolderPath? path = null;
        var steps = this.special_use_paths.get(use);
        if (steps != null) {
            path = root;
            foreach (string step in steps) {
                path = path.get_child(step);
            }
        }
        return path;
    }

    /**
     * Returns the configured special folder use for a given path.
     */
    public Folder.SpecialUse get_folder_use_for_path(FolderPath path) {
        var path_steps = path.as_array();
        var use = Folder.SpecialUse.NONE;
        foreach (var entry in this.special_use_paths.entries) {
            var use_steps = entry.value;
            var found = false;
            if (path_steps.length == use_steps.size) {
                found = true;
                for (int i = path_steps.length - 1; i >= 0; i--) {
                    if (path_steps[i] != use_steps[i]) {
                        found = false;
                        break;
                    }
                }
            }
            if (found) {
                use = entry.key;
                break;
            }
        }
        return use;
    }

    /**
     * Returns the best credentials to use for the outgoing service.
     *
     * This method checks for an outgoing service that use incoming
     * service's credentials for authentication and if enabled,
     * returns those. If this method returns null, then outgoing
     * authentication should not be attempted for this account.
     */
    public Credentials? get_outgoing_credentials() {
        Credentials? outgoing = null;
        switch (this.outgoing.credentials_requirement) {
        case USE_INCOMING:
            outgoing = this.incoming.credentials;
            break;
        case CUSTOM:
            outgoing = this.outgoing.credentials;
            break;
        case NONE:
            // no-op
            break;
        }
        return outgoing;
    }

    /**
     * Loads the authentication token for the outgoing service.
     *
     * Credentials are loaded from the mediator, thus it may yield for
     * some time.
     *
     * Returns true if the credential's token was successfully loaded
     * or are not needed (that is, if the credentials are null), or
     * false if the token could not be loaded and the service's
     * credentials are invalid.
     */
    public async bool load_outgoing_credentials(GLib.Cancellable? cancellable)
        throws GLib.Error {
        Credentials? creds = get_outgoing_credentials();
        bool loaded = true;
        if (creds != null) {
            if (this.outgoing.credentials_requirement == USE_INCOMING) {
                loaded = yield this.mediator.load_token(
                    this, this.incoming, cancellable
                );
            } else {
                loaded = yield this.mediator.load_token(
                    this, this.outgoing, cancellable
                );
            }
        }
        return loaded;
    }

    /**
     * Loads the authentication token for the incoming service.
     *
     * Credentials are loaded from the mediator, thus it may yield for
     * some time.
     *
     * Returns true if the credential's token was successfully loaded
     * or are not needed (that is, if the credentials are null), or
     * false if the token could not be loaded and the service's
     * credentials are invalid.
     */
    public async bool load_incoming_credentials(GLib.Cancellable? cancellable)
        throws GLib.Error {
        Credentials? creds = this.incoming.credentials;
        bool loaded = true;
        if (creds != null) {
            loaded = yield this.mediator.load_token(
                this, this.incoming, cancellable
            );
        }
        return loaded;
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
                this.label == other.label &&
                this.primary_mailbox.equal_to(other.primary_mailbox) &&
                this.sender_mailboxes.size == other.sender_mailboxes.size &&
                traverse(this.sender_mailboxes).all(
                    addr => other.sender_mailboxes.contains(addr)
                ) &&
                this.prefetch_period_days == other.prefetch_period_days &&
                this.save_sent == other.save_sent &&
                this.save_drafts == other.save_drafts &&
                this.use_signature == other.use_signature &&
                this.signature == other.signature &&
                this.incoming.equal_to(other.incoming) &&
                this.outgoing.equal_to(other.outgoing) &&
                this.special_use_paths.size == other.special_use_paths.size &&
                this.special_use_paths.has_all(other.special_use_paths) &&
                this.config_dir == other.config_dir &&
                this.data_dir == other.data_dir
            )
        );
    }

}
