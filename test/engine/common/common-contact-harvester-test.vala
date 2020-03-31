/*
 * Copyright 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */


class Geary.ContactHarvesterImplTest : TestCase {


    private ContactStoreMock? store = null;
    private Email? email = null;
    private RFC822.MailboxAddress test_address = null;
    private RFC822.MailboxAddress sender_address = null;
    private Gee.Collection<RFC822.MailboxAddress> senders = null;


    public ContactHarvesterImplTest() {
        base("Geary.ContactHarvesterImplTest");
        add_test("whitelisted_folder_type", whitelisted_folder_type);
        add_test("blacklisted_folder_type", blacklisted_folder_type);
        add_test("seen_priority", seen_priority);
        add_test("sent_priority", sent_priority);
        add_test("received_priority", received_priority);
    }

    public override void set_up() throws GLib.Error {
        this.store = new ContactStoreMock();
        this.email = new Email(
            new ImapDB.EmailIdentifier.no_message_id(new Imap.UID(1))
        );
        // Ensure the minimum required email flags are set
        this.email.set_originators(null, null, null);
        this.email.set_receivers(null, null, null);

        this.test_address = new RFC822.MailboxAddress(
            "Test", "test@example.com"
        );
        this.sender_address = new RFC822.MailboxAddress(
            "Sender", "sender@example.com"
        );
        this.senders = Collection.single(this.sender_address);
    }

    public override void tear_down() throws GLib.Error {
        this.store = null;
        this.email = null;
        this.test_address = null;
        this.sender_address = null;
        this.senders = null;
    }

    public void whitelisted_folder_type() throws GLib.Error {
        ContactHarvesterImpl whitelisted = new ContactHarvesterImpl(
            this.store,
            INBOX,
            this.senders
        );
        this.store.expect_call("get_by_rfc822");
        ExpectedCall update_call = this.store.expect_call("update_contacts");
        this.email.set_receivers(
            new RFC822.MailboxAddresses.single(this.test_address), null, null
        );

        whitelisted.harvest_from_email.begin(
            Collection.single(this.email), null,
            (obj, ret) => { async_complete(ret); }
        );
        whitelisted.harvest_from_email.end(async_result());

        this.store.assert_expectations();

        Gee.Collection<Contact> contacts = update_call.called_arg<Gee.Collection<Contact>>(0);
        assert_int(1, contacts.size, "contacts length");
        Contact? created = Collection.first(contacts) as Contact;
        assert_non_null(created, "contacts contents");

        assert_string("Test", created.real_name);
        assert_string("test@example.com", created.email);
        assert_string("test@example.com", created.normalized_email);
    }

    public void blacklisted_folder_type() throws GLib.Error {
        ContactHarvesterImpl whitelisted = new ContactHarvesterImpl(
            this.store,
            JUNK,
            this.senders
        );
        this.email.set_receivers(
            new RFC822.MailboxAddresses.single(this.test_address), null, null
        );

        whitelisted.harvest_from_email.begin(
            Collection.single(this.email), null,
            (obj, ret) => { async_complete(ret); }
        );
        whitelisted.harvest_from_email.end(async_result());

        this.store.assert_expectations();
    }

    public void seen_priority() throws GLib.Error {
        ContactHarvesterImpl whitelisted = new ContactHarvesterImpl(
            this.store,
            INBOX,
            this.senders
        );
        this.store.expect_call("get_by_rfc822");
        ExpectedCall update_call = this.store.expect_call("update_contacts");
        this.email.set_receivers(
            new RFC822.MailboxAddresses.single(this.test_address), null, null
        );

        whitelisted.harvest_from_email.begin(
            Collection.single(this.email), null,
            (obj, ret) => { async_complete(ret); }
        );
        whitelisted.harvest_from_email.end(async_result());

        this.store.assert_expectations();

        Gee.Collection<Contact> contacts = update_call.called_arg<Gee.Collection<Contact>>(0);
        Contact? created = Collection.first(contacts) as Contact;
        assert_int(
            Contact.Importance.SEEN,
            created.highest_importance,
            "call contact importance"
        );
    }

    public void sent_priority() throws GLib.Error {
        ContactHarvesterImpl whitelisted = new ContactHarvesterImpl(
            this.store,
            SENT,
            this.senders
        );
        this.store.expect_call("get_by_rfc822");
        ExpectedCall update_call = this.store.expect_call("update_contacts");
        this.email.set_receivers(
            new RFC822.MailboxAddresses.single(this.test_address), null, null
        );

        whitelisted.harvest_from_email.begin(
            Collection.single(this.email), null,
            (obj, ret) => { async_complete(ret); }
        );
        whitelisted.harvest_from_email.end(async_result());

        this.store.assert_expectations();

        Gee.Collection<Contact> contacts = update_call.called_arg<Gee.Collection<Contact>>(0);
        Contact? created = Collection.first(contacts) as Contact;
        assert_int(
            Contact.Importance.SENT_TO,
            created.highest_importance,
            "call contact importance"
        );
    }

    public void received_priority() throws GLib.Error {
        ContactHarvesterImpl whitelisted = new ContactHarvesterImpl(
            this.store,
            SENT,
            this.senders
        );
        this.store.expect_call("get_by_rfc822");
        ExpectedCall update_call = this.store.expect_call("update_contacts");
        this.email.set_receivers(
            new RFC822.MailboxAddresses.single(this.sender_address), null, null
        );

        whitelisted.harvest_from_email.begin(
            Collection.single(this.email), null,
            (obj, ret) => { async_complete(ret); }
        );
        whitelisted.harvest_from_email.end(async_result());

        this.store.assert_expectations();

        Gee.Collection<Contact> contacts = update_call.called_arg<Gee.Collection<Contact>>(0);
        Contact? created = Collection.first(contacts) as Contact;
        assert_int(
            Contact.Importance.RECEIVED_FROM,
            created.highest_importance,
            "call contact importance"
        );
    }

}
