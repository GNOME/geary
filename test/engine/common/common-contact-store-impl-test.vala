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
        add_test("search_utf8_latin_names", search_utf8_latin_names);
        add_test("search_utf8_multi_byte_names", search_utf8_multi_byte_names);
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
            this.async_completion
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
            this.async_completion
        );
        Contact? existing = test_article.get_by_rfc822.end(async_result());
        assert_non_null(existing, "Existing contact");
        assert_equal(existing.email, "Test@example.com", "Existing email");
        assert_equal(existing.normalized_email, "test@example.com", "Existing normalized_email");
        assert_equal(existing.real_name, "Test Name", "Existing real_name");
        assert_equal<int?>(existing.highest_importance, 50, "Existing highest_importance");
        assert_false(existing.flags.always_load_remote_images(), "Existing flags");

        test_article.get_by_rfc822.begin(
            new RFC822.MailboxAddress(null, "test@example.com"),
            null,
            this.async_completion
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
            this.async_completion
        );
        Gee.Collection<Contact> results = test_article.search.end(
            async_result()
        );
        assert_equal(results.size, 0);
    }

    public void search_email_match() throws GLib.Error {
        test_article.search.begin(
            "Test@example",
            0,
            10,
            null,
            this.async_completion
        );
        Gee.Collection<Contact> results = test_article.search.end(
            async_result()
        );
        assert_equal<int?>(results.size, 1, "results.size");

        Contact search_hit = Collection.first(results);
        assert_equal(search_hit.email, "Test@example.com", "Existing email");
        assert_equal(search_hit.normalized_email, "test@example.com", "Existing normalized_email");
        assert_equal(search_hit.real_name, "Test Name", "Existing real_name");
        assert_equal<int?>(search_hit.highest_importance, 50, "Existing highest_importance");
        assert_false(search_hit.flags.always_load_remote_images(), "Existing flags");
    }

    public void search_name_match() throws GLib.Error {
        test_article.search.begin(
            "Test Name",
            0,
            10,
            null,
            this.async_completion
        );
        Gee.Collection<Contact> results = test_article.search.end(
            async_result()
        );
        assert_equal<int?>(results.size, 1, "results.size");

        Contact search_hit = Collection.first(results);
        assert_equal(search_hit.email, "Test@example.com", "Existing email");
        assert_equal(search_hit.normalized_email, "test@example.com", "Existing normalized_email");
        assert_equal(search_hit.real_name, "Test Name", "Existing real_name");
        assert_equal<int?>(search_hit.highest_importance, 50, "Existing highest_importance");
        assert_false(search_hit.flags.always_load_remote_images(), "Existing flags");
    }

    public void search_utf8_latin_names() throws GLib.Error {
        this.db.exec("""
            INSERT INTO ContactTable (
                real_name,
                email,
                normalized_email,
                highest_importance
            ) VALUES (
                'Germán',
                'latin@example.com',
                'latin@example.com',
                50
            );
        """);
        test_article.search.begin(
            "germá",
            0,
            10,
            null,
            this.async_completion
        );
        Gee.Collection<Contact> results = test_article.search.end(
            async_result()
        );
        assert_equal<int?>(results.size, 1, "results.size");

        Contact search_hit = Collection.first(results);
        assert_equal(search_hit.real_name, "Germán", "Existing real_name");
    }

    public void search_utf8_multi_byte_names() throws GLib.Error {
        this.db.exec("""
            INSERT INTO ContactTable (
                real_name,
                email,
                normalized_email,
                highest_importance
            ) VALUES (
                '年収1億円目指せ',
                'cjk@example.com',
                'cjk@example.com',
                50
            );
        """);

        test_article.search.begin(
            "年収",
            0,
            10,
            null,
            this.async_completion
        );
        Gee.Collection<Contact> results = test_article.search.end(
            async_result()
        );
        assert_equal<int?>(results.size, 1, "results.size");

        Contact search_hit = Collection.first(results);
        assert_equal(search_hit.real_name, "年収1億円目指せ", "Existing real_name");
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
            this.async_completion
        );
        test_article.update_contacts.end(async_result());

        test_article.get_by_rfc822.begin(
            new RFC822.MailboxAddress(null, "New@example.com"),
            null,
            this.async_completion
        );
        Contact? persisted = test_article.get_by_rfc822.end(async_result());
        assert_non_null(persisted, "persisted");
        assert_equal(persisted.email, "New@example.com", "Persisted email");
        assert_equal(persisted.normalized_email, "new@example.com", "Persisted normalized_email");
        assert_equal(persisted.real_name, "New", "Persisted real_name");
        assert_equal<int?>(persisted.highest_importance, 0, "Persisted highest_importance");
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
            this.async_completion
        );
        test_article.update_contacts.end(async_result());
        test_article.get_by_rfc822.begin(
            new RFC822.MailboxAddress(null, "Test@example.com"),
            null,
            this.async_completion
        );
        Contact? updated = test_article.get_by_rfc822.end(async_result());
        assert_non_null(updated, "updated");
        assert_equal(updated.email, "Test@example.com", "Updated email");
        assert_equal(updated.normalized_email, "test@example.com", "Updated normalized_email");
        assert_equal(updated.real_name, "Updated", "Updated real_name");
        assert_equal<int?>(updated.highest_importance, 100, "Updated highest_importance");
        assert_true(updated.flags.always_load_remote_images(), "Added flags");

        // Now try removing the flag and ensure it sticks
        not_updated.flags.remove(Contact.Flags.ALWAYS_LOAD_REMOTE_IMAGES);
        test_article.update_contacts.begin(
            Collection.single(not_updated),
            null,
            this.async_completion
        );
        test_article.update_contacts.end(async_result());
        test_article.get_by_rfc822.begin(
            new RFC822.MailboxAddress(null, "Test@example.com"),
            null,
            this.async_completion
        );
        Contact? updated_again = test_article.get_by_rfc822.end(async_result());
        assert_false(updated_again.flags.always_load_remote_images(), "Removed flags");
    }

}
