/*
 * Copyright 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * Contacts loader and cache for an account.
 *
 * This class aggregates contact information from Folks, the Engine,
 * and the source mailbox. It allows contacts for a specific account
 * to be obtained, and uses caches to minimise performance impact of
 * re-using recently used contacts.
 */
public class Application.ContactStore : Geary.BaseObject {


    // Keep caches small to keep lookups fast and memory overhead
    // low. Conversations are rarely more than in the 100's anyway.
    private const uint LRU_CACHE_MAX = 128;


    private static inline string to_cache_key(string value) {
        return value.normalize().casefold();
    }


    /** The account this store aggregates data for. */
    public Geary.Account account { get; private set; }

    internal Folks.IndividualAggregator individuals;

    // Cache for storing Folks individuals by email address. Store
    // nulls so that negative lookups are cached as well.
    private Util.Cache.Lru<Folks.Individual?> folks_address_cache =
        new Util.Cache.Lru<Folks.Individual?>(LRU_CACHE_MAX);

    // Cache for contacts backed by Folks individual's id.
    private Util.Cache.Lru<Contact> contact_id_cache =
        new Util.Cache.Lru<Contact>(LRU_CACHE_MAX);

    // Cache for engine contacts by email address.
    private Util.Cache.Lru<Geary.Contact> engine_address_cache =
        new Util.Cache.Lru<Geary.Contact>(LRU_CACHE_MAX);


    /** Constructs a new contact store for an account. */
    public ContactStore(Geary.Account account,
                        Folks.IndividualAggregator individuals) {
        this.account = account;
        this.individuals = individuals;
        this.individuals.individuals_changed_detailed.connect(
            on_individuals_changed
        );
    }

    ~ContactStore() {
        this.individuals.individuals_changed_detailed.disconnect(
            on_individuals_changed
        );
    }

    /** Closes the store, flushing all caches. */
    public void close() {
        this.folks_address_cache.clear();
        this.contact_id_cache.clear();
        this.engine_address_cache.clear();
    }

    /**
     * Returns a contact for a specific mailbox.
     *
     * Returns a contact that has the given mailbox address listed as
     * a primary or secondary email. A contact will always be
     * returned, so if no matching contact already exists a new,
     * non-persistent contact will be returned.
     */
    public async Contact load(Geary.RFC822.MailboxAddress mailbox,
                              GLib.Cancellable? cancellable)
        throws GLib.Error {
        Folks.Individual? individual = null;
        // Do a double lookup here in case of cache hit since null
        // values are used to be able to cache Folks lookup failures
        // (as well as successes).
        string email_key = to_cache_key(mailbox.address);
        if (this.folks_address_cache.has_key(email_key)) {
            individual = this.folks_address_cache.get_entry(email_key);
        } else {
            individual = yield search_folks_by_email(
                mailbox.address, cancellable
            );
            this.folks_address_cache.set_entry(email_key, individual);
        }

        return yield get_contact(individual, mailbox, cancellable);
    }

    internal async Geary.Contact
        lookup_engine_contact(Geary.RFC822.MailboxAddress mailbox,
                              GLib.Cancellable cancellable)
        throws GLib.Error {
        string email_key = to_cache_key(mailbox.address);
        Geary.Contact contact = this.engine_address_cache.get_entry(email_key);
        if (contact == null) {
            contact = yield this.account.contact_store.get_by_rfc822(
                mailbox, cancellable
            );
            if (contact == null) {
                contact = new Geary.Contact.from_rfc822_address(mailbox, 0);
                yield this.account.contact_store.update_contacts(
                    Geary.Collection.single(contact), cancellable
                );
            }
            this.engine_address_cache.set_entry(email_key, contact);
        }
        return contact;
    }

    private async Contact get_contact(Folks.Individual? individual,
                                      Geary.RFC822.MailboxAddress? mailbox,
                                      GLib.Cancellable? cancellable)
        throws GLib.Error {
        Contact? contact = null;
        if (individual != null) {
            contact = this.contact_id_cache.get_entry(individual.id);
            if (contact == null) {
                contact = new Contact.for_folks(this, individual);
                this.contact_id_cache.set_entry(individual.id, contact);
            }
        } else if (mailbox != null) {
            Geary.Contact engine = yield lookup_engine_contact(
                mailbox, cancellable
            );
            // Despite the engine's contact having a display name, use
            // the one from the source mailbox: Online services like
            // Gitlab will use the sender's name but the service's
            // email address, so the name from the engine probably
            // won't match the name on the email
            string name = (!Geary.String.is_empty_or_whitespace(mailbox.name) &&
                           !mailbox.is_spoofed())
               ? mailbox.name
               : mailbox.mailbox;
            contact = new Contact.for_engine(
                this, name, engine
            );
        } else {
            throw new Geary.EngineError.BAD_PARAMETERS(
                "Requires either an individual or a mailbox"
            );
        }
        return contact;
    }

    private async Folks.Individual? search_folks_by_email(string address,
                                                          GLib.Cancellable cancellable)
        throws GLib.Error {
        Folks.SearchView view = new Folks.SearchView(
            this.individuals,
            new Folks.SimpleQuery(
                address,
                new string[] {
                    Folks.PersonaStore.detail_key(
                        Folks.PersonaDetail.EMAIL_ADDRESSES
                    )
                }
            )
        );

        yield view.prepare();

        Folks.Individual? match = null;
        if (!view.individuals.is_empty) {
            match = view.individuals.first();
        }

        try {
            yield view.unprepare();
        } catch (GLib.Error err) {
            warning("Error unpreparing Folks search: %s", err.message);
        }

        if (cancellable.is_cancelled()) {
            throw new GLib.IOError.CANCELLED("Contact load was cancelled");
        }

        return match;
    }

    private void on_individuals_changed(
        Gee.MultiMap<Folks.Individual?,Folks.Individual?> changes) {
        foreach (Folks.Individual? individual in changes.get_keys()) {
            if (individual != null) {
                this.contact_id_cache.remove_entry(individual.id);
                foreach (Folks.EmailFieldDetails email in
                         individual.email_addresses) {
                    this.folks_address_cache.remove_entry(email.value);
                }
            }
        }
    }

}
