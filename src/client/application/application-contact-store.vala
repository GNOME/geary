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


    /** The account this store aggregates data for. */
    public Geary.Account account { get; private set; }

    internal Folks.IndividualAggregator individuals;

    // Cache for storing Folks individuals by email address. Store
    // nulls so that negative lookups are cached as well.
    private Util.Cache.Lru<Folks.Individual?> folks_address_cache =
        new Util.Cache.Lru<Folks.Individual?>(LRU_CACHE_MAX);

    // Cache for contacts backed by Folks individual's id.
    private Util.Cache.Lru<Contact?> contact_id_cache =
        new Util.Cache.Lru<Contact?>(LRU_CACHE_MAX);


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
        if (this.folks_address_cache.has_key(mailbox.address)) {
            individual = this.folks_address_cache.get_entry(mailbox.address);
        } else {
            individual = yield search_match(mailbox.address, cancellable);
            this.folks_address_cache.set_entry(mailbox.address, individual);
        }

        Contact? contact = null;
        if (individual != null) {
            this.contact_id_cache.get_entry(individual.id);
        }
        if (contact == null) {
            Geary.Contact? engine =
                this.account.get_contact_store().get_by_rfc822(mailbox);
            contact = new Contact(this, individual, engine, mailbox);
            if (individual != null) {
                this.contact_id_cache.set_entry(individual.id, contact);
            }
        }
        return contact;
    }

    private async Folks.Individual? search_match(string address,
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
