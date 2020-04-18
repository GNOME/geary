/*
 * Copyright © 2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * A factory for constructing plugin email stores and objects.
 *
 * This class provides a common implementation that shares email
 * objects between different plugin context instances.
 */
internal class Application.EmailStoreFactory : Geary.BaseObject {


    private const Geary.Email.Field REQUIRED_FIELDS = (
        ENVELOPE |
        FLAGS
    );


    private class EmailStoreImpl : Geary.BaseObject, Plugin.EmailStore {


        private weak EmailStoreFactory factory;


        public EmailStoreImpl(EmailStoreFactory factory) {
            this.factory = factory;
        }

        public override GLib.VariantType email_identifier_variant_type {
            get { return this._email_id_variant_type; }
        }
        private GLib.VariantType _email_id_variant_type = new GLib.VariantType(
            "(sv)"
        );

        public async Gee.Collection<Plugin.Email> get_email(
            Gee.Collection<Plugin.EmailIdentifier> plugin_ids,
            GLib.Cancellable? cancellable
        ) throws GLib.Error {
            var emails = new Gee.HashSet<Plugin.Email>();

            // The email could theoretically come from any account, so
            // group them by account up front. The common case will be
            // only a single account, so optimise for that a bit.

            var found_accounts = new Gee.HashMap<
                AccountContext, Gee.Set<Geary.EmailIdentifier>
            >();
            AccountContext? current_account = null;
            Gee.Set<Geary.EmailIdentifier>? engine_ids = null;
            foreach (Plugin.EmailIdentifier plugin_id in plugin_ids) {
                IdImpl? id_impl = plugin_id as IdImpl;
                if (id_impl != null) {
                    if (id_impl._account.backing != current_account) {
                        current_account = id_impl._account.backing;
                        engine_ids = found_accounts.get(current_account);
                        if (engine_ids == null) {
                            engine_ids = new Gee.HashSet<Geary.EmailIdentifier>();
                            found_accounts.set(current_account, engine_ids);
                        }
                    }
                    engine_ids.add(id_impl.backing);
                }
            }

            foreach (var context in found_accounts.keys) {
                Gee.Collection<Geary.Email> batch =
                    yield context.emails.list_email_by_sparse_id_async(
                        found_accounts.get(context),
                        REQUIRED_FIELDS,
                        NONE,
                        context.cancellable
                    );
                if (batch != null) {
                    foreach (var email in batch) {
                        emails.add(
                            new EmailImpl(
                                email,
                                this.factory.accounts.get(context))
                        );
                    }
                }
            }

            return emails;
        }

        public Plugin.EmailIdentifier? get_email_identifier_from_variant(
            GLib.Variant variant
        ) {
            var account = this.factory.get_account_from_variant(variant);
            var id = this.factory.get_email_identifier_from_variant(variant);
            IdImpl? plugin_id = null;
            if (account != null && id != null) {
                var plugin_account = this.factory.accounts.get(account);
                if (plugin_account != null) {
                    plugin_id = new IdImpl(id, plugin_account);
                }
            }
            return plugin_id;
        }

        internal void destroy() {
            // noop
        }

    }


    /** Implementation of the plugin email interface. */
    internal class EmailImpl : Geary.BaseObject, Plugin.Email {


        public Plugin.EmailIdentifier identifier {
            get {
                if (this._id == null) {
                    this._id = new IdImpl(this.backing.id, this.account);
                }
                return this._id;
            }
        }
        private IdImpl? _id = null;

        public Geary.EmailFlags flags {
            get { return this.backing.email_flags; }
        }

        public string subject {
            get { return this._subject; }
        }
        string _subject;

        internal Geary.Email backing { get; private set; }
        internal PluginManager.AccountImpl account { get; private set; }


        internal EmailImpl(Geary.Email backing,
                           PluginManager.AccountImpl account) {
            this.backing = backing;
            this.account = account;
            Geary.RFC822.Subject? subject = this.backing.subject;
            this._subject = subject != null ? subject.to_string() : "";
        }

        public Geary.RFC822.MailboxAddress? get_primary_originator() {
            return Util.Email.get_primary_originator(this.backing);
        }

    }


    internal class IdImpl : Geary.BaseObject,
        Gee.Hashable<Plugin.EmailIdentifier>, Plugin.EmailIdentifier {


        public Plugin.Account account { get { return this._account; } }
        internal PluginManager.AccountImpl _account { get; private set; }

        internal Geary.EmailIdentifier backing { get; private set; }


        internal IdImpl(Geary.EmailIdentifier backing,
                        PluginManager.AccountImpl account) {
            this.backing = backing;
            this._account = account;
        }

        public GLib.Variant to_variant() {
            return new GLib.Variant.tuple({
                    this._account.backing.account.information.id,
                        new GLib.Variant.variant(this.backing.to_variant())
            });
        }

        public bool equal_to(Plugin.EmailIdentifier other) {
            if (this == other) {
                return true;
            }
            var impl = other as IdImpl;
            return (
                impl != null &&
                this.backing.equal_to(impl.backing) &&
                this._account.backing == impl._account.backing
            );
        }

        public uint hash() {
            return this.backing.hash();
        }

    }


    private Gee.Map<AccountContext,PluginManager.AccountImpl> accounts;
    private Gee.Set<EmailStoreImpl> stores =
        new Gee.HashSet<EmailStoreImpl>();


    /**
     * Constructs a new factory instance.
     */
    public EmailStoreFactory(
        Gee.Map<AccountContext,PluginManager.AccountImpl> accounts
    ) {
        this.accounts = accounts;
    }

    /** Clearing all state of the store. */
    public void destroy() throws GLib.Error {
        foreach (EmailStoreImpl store in this.stores) {
            store.destroy();
        }
        this.stores.clear();
    }

    /** Constructs a new email store for use by plugin contexts. */
    public Plugin.EmailStore new_email_store() {
        var store = new EmailStoreImpl(this);
        this.stores.add(store);
        return store;
    }

    /** Destroys a folder store once is no longer required. */
    public void destroy_email_store(Plugin.EmailStore plugin) {
        EmailStoreImpl? impl = plugin as EmailStoreImpl;
        if (impl != null) {
            impl.destroy();
            this.stores.remove(impl);
        }
    }

    public Gee.Collection<Plugin.EmailIdentifier> to_plugin_ids(
        Gee.Collection<Geary.EmailIdentifier> engine_ids,
        AccountContext account
    ) {
        var plugin_ids = new Gee.HashSet<Plugin.EmailIdentifier>();
        foreach (var id in engine_ids) {
            plugin_ids.add(new IdImpl(id, this.accounts.get(account)));
        }
        return plugin_ids;
    }

    public Geary.EmailIdentifier? to_engine_id(Plugin.EmailIdentifier plugin) {
        var impl = plugin as IdImpl;
        return (impl != null) ? impl.backing : null;
    }

    public Plugin.Email to_plugin_email(Geary.Email engine,
                                        AccountContext account) {
        return new EmailImpl(engine, this.accounts.get(account));
    }

    /** Returns the account context for the given plugin email id. */
    public AccountContext get_account_from_variant(GLib.Variant target) {
        AccountContext? account = null;
        string id = (string) target.get_child_value(0);
        foreach (var context in this.accounts.keys) {
            var info = context.account.information;
            if (info.id == id) {
                account = context;
                break;
            }
        }
        return account;
    }

    /** Returns the engine email id for the given plugin email id. */
    public Geary.EmailIdentifier?
        get_email_identifier_from_variant(GLib.Variant target) {
        Geary.EmailIdentifier? id = null;
        var context = get_account_from_variant(target);
        if (context != null) {
            try {
                id = context.account.to_email_identifier(
                    target.get_child_value(1).get_variant()
                );
            } catch (GLib.Error err) {
                debug("Invalid email folder id: %s", err.message);
            }
        }
        return id;
    }

}
