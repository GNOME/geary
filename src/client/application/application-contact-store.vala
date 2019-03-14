/*
 * Copyright 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * A source of contacts for an account.
 *
 * This class aggregates data from for both the Engine and Folks,
 * allowing contacts for a specific account to be queried.
 */
public class Application.ContactStore : Geary.BaseObject {


    /** The account this store aggregates data for. */
    public Geary.Account account { get; private set; }

    private Folks.IndividualAggregator individuals;


    /** Constructs a new contact store for an account. */
    public ContactStore(Geary.Account account,
                        Folks.IndividualAggregator individuals) {
        this.account = account;
        this.individuals = individuals;
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
        Folks.Individual? individual = yield search_match(
            mailbox.address, cancellable
        );
        Geary.Contact? contact =
            this.account.get_contact_store().get_by_rfc822(mailbox);
        return new Contact(this, individual, contact, mailbox);
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

}
