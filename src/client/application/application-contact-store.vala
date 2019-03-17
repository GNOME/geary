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

    // Address for storing contacts for a specific email address.
    // This primary cache is used to fast-path common-case lookups.
    private Util.Cache.Lru<Contact> address_cache =
        new Util.Cache.Lru<Contact>(LRU_CACHE_MAX);

    // Folks cache used for storing contacts backed by a Folk
    // individual. This secondary cache is used in case an individual
    // has more than one email address.
    private Util.Cache.Lru<Contact> folks_cache =
        new Util.Cache.Lru<Contact>(LRU_CACHE_MAX);


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
        this.address_cache.clear();
        this.folks_cache.clear();
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
        Contact? contact = this.address_cache.get_entry(mailbox.address);
        if (contact == null) {
            Folks.Individual? individual = yield search_match(
                mailbox.address, cancellable
            );
            if (individual != null) {
                contact = this.folks_cache.get_entry(individual.id);
            }

            if (contact == null) {
                Geary.Contact? engine =
                    this.account.get_contact_store().get_by_rfc822(mailbox);
                contact = new Contact(this, individual, engine, mailbox);
                if (individual != null) {
                    this.folks_cache.set_entry(individual.id, contact);
                }
                this.address_cache.set_entry(mailbox.address, contact);
            }
        }
        return contact;
    }

    private async Folks.Individual? search_match(string address,
                                                 GLib.Cancellable cancellable)
        throws GLib.Error {
        if (cancellable.is_cancelled()) {
            throw new GLib.IOError.CANCELLED("Contact load was cancelled");
        }

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
        return match;
    }

    private void on_individuals_changed(
        Gee.MultiMap<Folks.Individual?,Folks.Individual?> changes) {
        foreach (Folks.Individual? individual in changes.get_keys()) {
            if (individual != null) {
                this.folks_cache.remove_entry(individual.id);
                foreach (Folks.EmailFieldDetails email in
                         individual.email_addresses) {
                    this.address_cache.remove_entry(email.value);
                }
            }
        }
    }

}
