/*
 * Copyright 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */


class Geary.ContactStoreImplTest : TestCase {


    private GLib.File? tmp_dir = null;
    private ImapDB.Database? db = null;
    private ContactStoreImpl? test_article = null;


    public ContactStoreImplTest() {
        base("Geary.ContactStoreImplTest");
        add_test("get_by_rfc822", get_by_rfc822);
        add_test("search_no_match", search_no_match);
        add_test("search_email_match", search_email_match);
        add_test("search_name_match", search_name_match);
        add_test("update_new_contact", update_new_contact);
        add_test("update_existing_contact", update_existing_contact);
    }

    public override void set_up() throws GLib.Error {
        this.tmp_dir = GLib.File.new_for_path(
            GLib.DirUtils.make_tmp("geary-contact-harvester-test-XXXXXX")
        );
        GLib.File db_file = this.tmp_dir.get_child("geary.db");
        GLib.File attachments_dir = this.tmp_dir.get_child("attachments");

        this.db = new ImapDB.Database(
            db_file,
            GLib.File.new_for_path(_SOURCE_ROOT_DIR).get_child("sql"),
            attachments_dir,
            new Geary.SimpleProgressMonitor(Geary.ProgressType.DB_UPGRADE),
            new Geary.SimpleProgressMonitor(Geary.ProgressType.DB_VACUUM)
        );
        this.db.open.begin(
            Geary.Db.DatabaseFlags.CREATE_FILE, null,
            (obj, ret) => { async_complete(ret); }
        );
        this.db.open.end(async_result());

        this.db.exec("""
INSERT INTO ContactTable (
    id,
    normalized_email,
    real_name,
    email,
    highest_importance
) VALUES (
    1,
    'test@example.com',
    'Test Name',
    'Test@example.com',
    50
);
""");

        this.test_article = new ContactStoreImpl(this.db);
    }

    public override void tear_down() throws GLib.Error {
        this.test_article = null;

        this.db.close();
        this.db = null;

        delete_file(this.tmp_dir);
        this.tmp_dir = null;
    }

    public void get_by_rfc822() throws GLib.Error {
        test_article.get_by_rfc822.begin(
            new RFC822.MailboxAddress(null, "Test@example.com"),
            null,
            (obj, ret) => { async_complete(ret); }
        );
        Contact? existing = test_article.get_by_rfc822.end(async_result());
        assert_non_null(existing, "Existing contact");
        assert_string("Test@example.com", existing.email, "Existing email");
        assert_string("test@example.com", existing.normalized_email, "Existing normalized_email");
        assert_string("Test Name", existing.real_name, "Existing real_name");
        assert_int(50, existing.highest_importance, "Existing highest_importance");
        assert_false(existing.flags.always_load_remote_images(), "Existing flags");

        test_article.get_by_rfc822.begin(
            new RFC822.MailboxAddress(null, "test@example.com"),
            null,
            (obj, ret) => { async_complete(ret); }
        );
        Contact? missing = test_article.get_by_rfc822.end(async_result());
        assert_null(missing, "Missing contact");
    }

    public void search_no_match() throws GLib.Error {
        test_article.search.begin(
            "blarg",
            0,
            10,
            null,
            (obj, ret) => { async_complete(ret); }
        );
        Gee.Collection<Contact> results = test_article.search.end(
            async_result()
        );
        assert_int(0, results.size);
    }

    public void search_email_match() throws GLib.Error {
        test_article.search.begin(
            "example.com",
            0,
            10,
            null,
            (obj, ret) => { async_complete(ret); }
        );
        Gee.Collection<Contact> results = test_article.search.end(
            async_result()
        );
        assert_int(1, results.size, "results.size");

        Contact search_hit = Collection.get_first(results);
        assert_string("Test@example.com", search_hit.email, "Existing email");
        assert_string("test@example.com", search_hit.normalized_email, "Existing normalized_email");
        assert_string("Test Name", search_hit.real_name, "Existing real_name");
        assert_int(50, search_hit.highest_importance, "Existing highest_importance");
        assert_false(search_hit.flags.always_load_remote_images(), "Existing flags");
    }

    public void search_name_match() throws GLib.Error {
        test_article.search.begin(
            "Test Name",
            0,
            10,
            null,
            (obj, ret) => { async_complete(ret); }
        );
        Gee.Collection<Contact> results = test_article.search.end(
            async_result()
        );
        assert_int(1, results.size, "results.size");

        Contact search_hit = Collection.get_first(results);
        assert_string("Test@example.com", search_hit.email, "Existing email");
        assert_string("test@example.com", search_hit.normalized_email, "Existing normalized_email");
        assert_string("Test Name", search_hit.real_name, "Existing real_name");
        assert_int(50, search_hit.highest_importance, "Existing highest_importance");
        assert_false(search_hit.flags.always_load_remote_images(), "Existing flags");
    }

    public void update_new_contact() throws GLib.Error {
        Contact not_persisted = new Contact(
            "New@example.com",
            "New",
            0,
            "new@example.com"
        );
        not_persisted.flags.add(Contact.Flags.ALWAYS_LOAD_REMOTE_IMAGES);
        test_article.update_contacts.begin(
            Collection.single(not_persisted),
            null,
            (obj, ret) => { async_complete(ret); }
        );
        test_article.update_contacts.end(async_result());

        test_article.get_by_rfc822.begin(
            new RFC822.MailboxAddress(null, "New@example.com"),
            null,
            (obj, ret) => { async_complete(ret); }
        );
        Contact? persisted = test_article.get_by_rfc822.end(async_result());
        assert_non_null(persisted, "persisted");
        assert_string("New@example.com", persisted.email, "Persisted email");
        assert_string("new@example.com", persisted.normalized_email, "Persisted normalized_email");
        assert_string("New", persisted.real_name, "Persisted real_name");
        assert_int(0, persisted.highest_importance, "Persisted highest_importance");
        assert_true(persisted.flags.always_load_remote_images(), "Persisted real_name");
    }

    public void update_existing_contact() throws GLib.Error {
        Contact not_updated = new Contact(
            "Test@example.com",
            "Updated",
            100,
            "new@example.com"
        );
        not_updated.flags.add(Contact.Flags.ALWAYS_LOAD_REMOTE_IMAGES);
        test_article.update_contacts.begin(
            Collection.single(not_updated),
            null,
            (obj, ret) => { async_complete(ret); }
        );
        test_article.update_contacts.end(async_result());
        test_article.get_by_rfc822.begin(
            new RFC822.MailboxAddress(null, "Test@example.com"),
            null,
            (obj, ret) => { async_complete(ret); }
        );
        Contact? updated = test_article.get_by_rfc822.end(async_result());
        assert_non_null(updated, "updated");
        assert_string("Test@example.com", updated.email, "Updated email");
        assert_string("test@example.com", updated.normalized_email, "Updated normalized_email");
        assert_string("Updated", updated.real_name, "Updated real_name");
        assert_int(100, updated.highest_importance, "Updated highest_importance");
        assert_true(updated.flags.always_load_remote_images(), "Updated real_name");
    }

}
