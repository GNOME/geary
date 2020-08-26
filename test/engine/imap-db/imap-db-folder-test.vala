/*
 * Copyright 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */


class Geary.ImapDB.FolderTest : TestCase {


    private GLib.File? tmp_dir = null;
    private Geary.AccountInformation? config = null;
    private Account? account = null;
    private Folder? folder = null;


    public FolderTest() {
        base("Geary.ImapDB.FolderTest");
        add_test("create_read_email", create_read_email);
        add_test("create_unread_email", create_unread_email);
        add_test("create_no_unread_update", create_no_unread_update);
        add_test("merge_email", merge_email);
        add_test("merge_add_flags", merge_add_flags);
        add_test("merge_remove_flags", merge_remove_flags);
        //add_test("merge_existing_preview", merge_existing_preview);
        add_test("set_flags", set_flags);
        add_test("set_flags_on_deleted", set_flags_on_deleted);
        add_test("detach_emails_before_timestamp", detach_emails_before_timestamp);
    }

    public override void set_up() throws GLib.Error {
        this.tmp_dir = GLib.File.new_for_path(
            GLib.DirUtils.make_tmp("geary-imap-db-account-test-XXXXXX")
        );

        this.config = new Geary.AccountInformation(
            "test",
            ServiceProvider.OTHER,
            new Mock.CredentialsMediator(),
            new Geary.RFC822.MailboxAddress(null, "test@example.com")
        );

        this.account = new Account(
            config,
            this.tmp_dir,
            GLib.File.new_for_path(_SOURCE_ROOT_DIR).get_child("sql")
        );
        this.account.open_async.begin(
            null,
            this.async_completion
        );
        this.account.open_async.end(async_result());

        this.account.db.exec(
            "INSERT INTO FolderTable (id, name) VALUES (1, 'test');"
        );

        this.account.list_folders_async.begin(
            this.account.imap_folder_root,
            null,
            this.async_completion
        );
        this.folder = traverse<Folder>(
            this.account.list_folders_async.end(async_result())
        ).first();
    }

    public override void tear_down() throws GLib.Error {
        this.folder = null;
        this.account.close_async.begin(
            null,
            this.async_completion
        );
        this.account.close_async.end(async_result());
        this.account = null;
        this.config = null;

        delete_file(this.tmp_dir);
        this.tmp_dir = null;
    }

    public void create_read_email() throws GLib.Error {
        Email mock = new_mock_remote_email(1, "test");

        this.folder.create_or_merge_email_async.begin(
            Collection.single(mock),
            true,
            new MockContactHarvester(),
            null,
            this.async_completion
        );
        Gee.Map<Email,bool> results =
            this.folder.create_or_merge_email_async.end(async_result());

        assert_equal<int?>(results.size, 1);
        assert_true(results.get(mock));
        assert_equal(this.folder.get_properties().email_unread, 0);
    }

    public void create_unread_email() throws GLib.Error {
        Email mock = new_mock_remote_email(
            1, "test", new EmailFlags.with(EmailFlags.UNREAD)
        );

        this.folder.create_or_merge_email_async.begin(
            Collection.single(mock),
            true,
            new MockContactHarvester(),
            null,
            this.async_completion
        );
        Gee.Map<Email,bool> results =
            this.folder.create_or_merge_email_async.end(async_result());

        assert_equal<int?>(results.size, 1);
        assert_true(results.get(mock));
        assert_equal<int?>(this.folder.get_properties().email_unread, 1);
    }

    public void create_no_unread_update() throws GLib.Error {
        Email mock = new_mock_remote_email(
            1, "test", new EmailFlags.with(EmailFlags.UNREAD)
        );

        this.folder.create_or_merge_email_async.begin(
            Collection.single(mock),
            false,
            new MockContactHarvester(),
            null,
            this.async_completion
        );
        Gee.Map<Email,bool> results =
            this.folder.create_or_merge_email_async.end(async_result());

        assert_equal<int?>(results.size, 1);
        assert_true(results.get(mock));
        assert_equal<int?>(this.folder.get_properties().email_unread, 0);
    }

    public void merge_email() throws GLib.Error {
        Email.Field fixture_fields = Email.Field.RECEIVERS;
        string fixture_to = "test@example.com";
        this.account.db.exec(
            "INSERT INTO MessageTable (id, fields, to_field) " +
            "VALUES (1, %d, '%s');".printf(fixture_fields, fixture_to)
        );
        this.account.db.exec("""
            INSERT INTO MessageLocationTable (id, message_id, folder_id, ordering)
                VALUES (1, 1, 1, 1);
        """);

        string mock_subject = "test subject";
        Email mock = new_mock_remote_email(1, mock_subject);

        this.folder.create_or_merge_email_async.begin(
            Collection.single(mock),
            true,
            new MockContactHarvester(),
            null,
            this.async_completion
        );
        Gee.Map<Email,bool> results =
            this.folder.create_or_merge_email_async.end(async_result());

        assert_equal<int?>(results.size, 1);
        assert_true(!results.get(mock));

        // Fetch it again to make sure it's been merged using required
        // fields to check
        this.folder.fetch_email_async.begin(
            (EmailIdentifier) mock.id,
            fixture_fields | mock.fields,
            Folder.ListFlags.NONE,
            null,
            this.async_completion
        );
        Email? merged = null;
        try {
            merged = this.folder.fetch_email_async.end(async_result());
        } catch (EngineError.INCOMPLETE_MESSAGE err) {
            assert_no_error(err);
        }

        assert_equal(merged.to.to_string(), fixture_to);
        assert_equal(merged.subject.to_string(), mock_subject);
    }

    public void merge_add_flags() throws GLib.Error {
        // Flags in the DB are expected to be Imap.MessageFlags
        Email.Field fixture_fields = Email.Field.FLAGS;
        Imap.MessageFlags fixture_flags =
            new Imap.MessageFlags(Collection.single(Imap.MessageFlag.SEEN));
        this.account.db.exec(
            "INSERT INTO MessageTable (id, fields, flags) " +
            "VALUES (1, %d, '%s');".printf(
                fixture_fields, fixture_flags.serialize()
            )
        );
        this.account.db.exec("""
            INSERT INTO MessageLocationTable (id, message_id, folder_id, ordering)
                VALUES (1, 1, 1, 1);
        """);

        EmailFlags test_flags = new EmailFlags.with(EmailFlags.UNREAD);
        Email test = new_mock_remote_email(1, null, test_flags);
        this.folder.create_or_merge_email_async.begin(
            Collection.single(test),
            true,
            new MockContactHarvester(),
            null,
            this.async_completion
        );
        Gee.Map<Email,bool> results =
            this.folder.create_or_merge_email_async.end(async_result());

        assert_equal<int?>(results.size, 1);
        assert_false(results.get(test));

        assert_flags((EmailIdentifier) test.id, test_flags);
    }

    public void merge_remove_flags() throws GLib.Error {
        // Flags in the DB are expected to be Imap.MessageFlags
        Email.Field fixture_fields = Email.Field.FLAGS;
        Imap.MessageFlags fixture_flags =
            new Imap.MessageFlags(Gee.Collection.empty<Geary.Imap.MessageFlag>());
        this.account.db.exec(
            "INSERT INTO MessageTable (id, fields, flags) " +
            "VALUES (1, %d, '%s');".printf(
                fixture_fields, fixture_flags.serialize()
            )
        );
        this.account.db.exec("""
            INSERT INTO MessageLocationTable (id, message_id, folder_id, ordering)
                VALUES (1, 1, 1, 1);
        """);

        EmailFlags test_flags = new EmailFlags();
        Email test = new_mock_remote_email(1, null, test_flags);
        this.folder.create_or_merge_email_async.begin(
            Collection.single(test),
            true,
            new MockContactHarvester(),
            null,
            this.async_completion
        );
        Gee.Map<Email,bool> results =
            this.folder.create_or_merge_email_async.end(async_result());

        assert_equal<int?>(results.size, 1);
        assert_false(results.get(test));

        assert_flags((EmailIdentifier) test.id, test_flags);
    }

    public void set_flags() throws GLib.Error {
        // Note: Flags in the DB are expected to be Imap.MessageFlags,
        // and flags passed in to ImapDB.Folder are expected to be
        // Imap.EmailFlags

        Email.Field fixture_fields = Email.Field.FLAGS;
        Imap.MessageFlags fixture_flags =
            new Imap.MessageFlags(Collection.single(Imap.MessageFlag.SEEN));
        this.account.db.exec(
            "INSERT INTO MessageTable (id, fields, flags) " +
            "VALUES (1, %d, '%s');".printf(
                fixture_fields, fixture_flags.serialize()
            )
        );
        this.account.db.exec("""
            INSERT INTO MessageLocationTable (id, message_id, folder_id, ordering)
                VALUES (1, 1, 1, 1);
        """);

        Imap.EmailFlags test_flags = Imap.EmailFlags.from_api_email_flags(
            new EmailFlags.with(EmailFlags.UNREAD)
        );
        EmailIdentifier test = new EmailIdentifier(1, new Imap.UID(1));

        this.folder.set_email_flags_async.begin(
            Collection.single_map(test, test_flags),
            null,
            this.async_completion
        );
        this.folder.set_email_flags_async.end(async_result());

        assert_flags(test, test_flags);
    }

    public void set_flags_on_deleted() throws GLib.Error {
        // Note: Flags in the DB are expected to be Imap.MessageFlags,
        // and flags passed in to ImapDB.Folder are expected to be
        // Imap.EmailFlags

        Email.Field fixture_fields = Email.Field.FLAGS;
        Imap.MessageFlags fixture_flags =
            new Imap.MessageFlags(Collection.single(Imap.MessageFlag.SEEN));
        this.account.db.exec(
            "INSERT INTO MessageTable (id, fields, flags) " +
            "VALUES (1, %d, '%s');".printf(
                fixture_fields, fixture_flags.serialize()
            )
        );
        this.account.db.exec("""
            INSERT INTO MessageLocationTable
                (id, message_id, folder_id, ordering, remove_marker)
                VALUES
                (1, 1, 1, 1, 1);
        """);

        Imap.EmailFlags test_flags = Imap.EmailFlags.from_api_email_flags(
            new EmailFlags.with(EmailFlags.UNREAD)
        );
        EmailIdentifier test = new EmailIdentifier(1, new Imap.UID(1));

        this.folder.set_email_flags_async.begin(
            Collection.single_map(test, test_flags),
            null,
            this.async_completion
        );
        this.folder.set_email_flags_async.end(async_result());

        assert_flags(test, test_flags);
    }

    public void detach_emails_before_timestamp() throws GLib.Error {
        // Ensures that messages outside the folder and within the epoch aren't
        // removed, and that messages meeting the criteria are removed.

        this.account.db.exec(
            "INSERT INTO FolderTable (id, name) VALUES (2, 'other');"
        );

        GLib.DateTime threshold = new GLib.DateTime.local(2020, 1, 1, 0, 0, 0);
        GLib.DateTime beyond_threshold = new GLib.DateTime.local(2019, 1, 1, 0, 0, 0);
        GLib.DateTime within_threshold = new GLib.DateTime.local(2021, 1, 1, 0, 0, 0);

        Email.Field fixture_fields = Email.Field.RECEIVERS;
        string fixture_to = "test1@example.com";
        this.account.db.exec(
            "INSERT INTO MessageTable (id, fields, to_field, internaldate_time_t) " +
            "VALUES (1, %d, '%s', %s);".printf(fixture_fields,
                                               fixture_to,
                                               within_threshold.to_unix().to_string())
        );
        this.account.db.exec(
            "INSERT INTO MessageTable (id, fields, to_field, internaldate_time_t) " +
            "VALUES (2, %d, '%s', %s);".printf(fixture_fields,
                                               fixture_to,
                                               within_threshold.to_unix().to_string())
        );
        this.account.db.exec(
            "INSERT INTO MessageTable (id, fields, to_field, internaldate_time_t) " +
            "VALUES (3, %d, '%s', %s);".printf(fixture_fields,
                                               fixture_to,
                                               beyond_threshold.to_unix().to_string())
        );

        this.account.db.exec("""
            INSERT INTO MessageLocationTable
                (id, message_id, folder_id, ordering, remove_marker)
                VALUES
                (1, 1, 1, 1, 1),
                (2, 2, 2, 1, 1),
                (3, 3, 1, 2, 1);
        """);

        for (int i = 4; i <= 200; i++) {
            this.account.db.exec(
                "INSERT INTO MessageTable (id, fields, to_field, internaldate_time_t) " +
                "VALUES (%d, %d, '%s', %s);".printf(i,
                                                fixture_fields,
                                                fixture_to,
                                                beyond_threshold.to_unix().to_string())
            );
            this.account.db.exec(
                "INSERT INTO MessageLocationTable " + 
                "    (id, message_id, folder_id, ordering, remove_marker) " + 
                "VALUES (%d, %d, 1, %d, 1);".printf(i, i, i)
            );
        }


        this.folder.detach_emails_before_timestamp.begin(
            threshold,
            null,
            this.async_completion
        );
        this.folder.detach_emails_before_timestamp.end(async_result());

        int64[] expected = { 1, 2 };
        Db.Result result = this.account.db.query(
            "SELECT id FROM MessageLocationTable WHERE id IN (1, 2);"
        );

        int i = 0;
        while (!result.finished) {
            assert_true(i < expected.length, "Too many rows");
            assert_equal<int64?>(result.int64_at(0), expected[i]);
            i++;
            result.next();
        }
        assert_true(i == expected.length, "Not enough rows");

        result = this.account.db.query(
            "SELECT COUNT(id) FROM MessageLocationTable WHERE folder_id = 1;"
        );
        assert_false(result.finished);
        assert_equal<int64?>(result.int64_at(0), 100);
        result.next();
    }

    private Email new_mock_remote_email(int64 uid,
                                        string? subject = null,
                                        Geary.EmailFlags? flags = null) {
        Email mock = new Email(
            new EmailIdentifier.no_message_id(new Imap.UID(uid))
        );
        if (subject != null) {
            mock.set_message_subject(new RFC822.Subject(subject));
        }
        // Flags passed in to ImapDB.Folder are expected to be
        // Imap.EmailFlags
        if (flags != null) {
            mock.set_flags(Imap.EmailFlags.from_api_email_flags(flags));
        }
        return mock;
    }

    private void assert_flags(EmailIdentifier id, EmailFlags expected)
        throws GLib.Error {
        this.folder.fetch_email_async.begin(
            id,
            Email.Field.FLAGS,
            Folder.ListFlags.INCLUDE_MARKED_FOR_REMOVE,
            null,
            this.async_completion
        );
        Email? merged = null;
        try {
            merged = this.folder.fetch_email_async.end(async_result());
        } catch (EngineError.INCOMPLETE_MESSAGE err) {
            assert_no_error(err);
        }

        assert_true(
            expected.equal_to(merged.email_flags),
            "Unexpected merged flags: %s".printf(merged.to_string())
        );
    }

}
