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
public class Application.ContactStore {


    /** The account this store aggregates data for. */
    public Geary.Account account { get; private set; }


    /** Constructs a new contact store for an account. */
    public ContactStore(Geary.Account account) {
        this.account = account;
    }

    /**
     * Returns a contact for a specific mailbox.
     *
     * Returns a contact that has the given mailbox address listed as
     * a primary or secondary email. A contact will always be
     * returned, so if no matching contact already exists a new,
     * non-persistent contact will be returned.
     */
    public Contact get(Geary.RFC822.MailboxAddress mailbox) {
        Geary.Contact? contact =
            this.account.get_contact_store().get_by_rfc822(mailbox);
        return new Contact(this, contact, mailbox);
    }

}
