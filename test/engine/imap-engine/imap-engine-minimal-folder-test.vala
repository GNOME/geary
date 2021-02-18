/*
 * Copyright © 2021 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

internal class Geary.ImapEngine.MinimalFolderTest : AccountBasedTest {


    private GenericAccount? account = null;
    private ImapDB.Folder? local_folder = null;


    public MinimalFolderTest() {
        base("Geary.ImapEngine.MinimalFolderTest");
        add_test("get_email_by_id", get_email_by_id);
        add_test("get_multiple_email_by_id", get_multiple_email_by_id);
        add_test("list_email_range_by_null_id", list_email_range_by_null_id);
        add_test(
            "list_email_range_by_non_null_id_descending",
            list_email_range_by_non_null_id_descending
        );
        add_test(
            "list_email_range_by_non_null_id_ascending",
            list_email_range_by_non_null_id_ascending
        );
        add_test(
            "list_email_range_by_id_partial",
            list_email_range_by_id_partial
        );
    }

    public override void set_up() throws GLib.Error {
        base.set_up();
        this.account = new_test_account();

        this.local_account.db.exec(
            "INSERT INTO FolderTable (id, name) VALUES (1, 'test');"
        );
        this.local_account.db.exec(
            "INSERT INTO MessageTable (id, fields, to_field, from_field) VALUES " +
            "(1, %d, '%s', null),".printf(
                Email.Field.RECEIVERS,
                "test1@example.com"
            ) +
            "(2, %d, '%s', '%s');".printf(
                (Email.Field.RECEIVERS | Email.Field.ORIGINATORS),
                "test2@example.com",
                "sender@example.com"
            )
        );
        this.local_account.db.exec("""
            INSERT INTO MessageLocationTable (id, message_id, folder_id, ordering)
                VALUES (1, 1, 1, 1), (2, 2, 1, 2);
        """);
        this.local_account.list_folders_async.begin(
            this.local_account.imap_folder_root,
            null,
            this.async_completion
        );
        this.local_folder = traverse<ImapDB.Folder>(
            this.local_account.list_folders_async.end(async_result())
        ).first();
    }

    public override void tear_down() throws GLib.Error {
        this.account = null;
        base.tear_down();
    }

    public void get_email_by_id() throws GLib.Error {
        var folder = new MinimalFolder(
            this.account,
            this.local_folder,
            NONE
        );
        var invalid_id = new ImapDB.EmailIdentifier(0, new Imap.UID(0));
        var valid_id = new ImapDB.EmailIdentifier(1, new Imap.UID(1));

        folder.get_email_by_id.begin(
            invalid_id, ALL, null, this.async_completion
        );
        try {
            folder.get_email_by_id.end(async_result());
            assert_not_reached();
        } catch (EngineError.NOT_FOUND err) {
            // all good
        }

        folder.get_email_by_id.begin(
            valid_id, RECEIVERS, null, this.async_completion
        );
        var email = folder.get_email_by_id.end(async_result());
        assert_true(email.id.equal_to(valid_id));
        assert_non_null(email.to);
        assert_equal<int?>(email.to.size, 1);
        assert_equal(email.to[0].address, "test1@example.com");

        folder.get_email_by_id.begin(
            valid_id, ALL, null, this.async_completion
        );
        try {
            folder.get_email_by_id.end(async_result());
            assert_not_reached();
        } catch (EngineError.INCOMPLETE_MESSAGE err) {
            // all good
        }
    }

    public void get_multiple_email_by_id() throws GLib.Error {
        var folder = new MinimalFolder(
            this.account,
            this.local_folder,
            NONE
        );
        var invalid_id = new ImapDB.EmailIdentifier(0, new Imap.UID(0));
        var valid_id = new ImapDB.EmailIdentifier(1, new Imap.UID(1));

        folder.get_multiple_email_by_id.begin(
            Collection.single(invalid_id), ALL, null, this.async_completion
        );
        try {
            folder.get_multiple_email_by_id.end(async_result());
            assert_not_reached();
        } catch (EngineError.NOT_FOUND err) {
            // all good
        }

        folder.get_multiple_email_by_id.begin(
            Collection.single(valid_id), RECEIVERS, null, this.async_completion
        );
        var email = assert_collection(
            folder.get_multiple_email_by_id.end(async_result())
        ).size(1)[0];
        assert_true(email.id.equal_to(valid_id));
        assert_non_null(email.to);
        assert_equal<int?>(email.to.size, 1);
        assert_equal(email.to[0].address, "test1@example.com");

        folder.get_multiple_email_by_id.begin(
            Collection.single(valid_id), ALL, null, this.async_completion
        );
        try {
            folder.get_multiple_email_by_id.end(async_result());
            assert_not_reached();
        } catch (EngineError.INCOMPLETE_MESSAGE err) {
            // all good
        }
    }

    public void list_email_range_by_null_id() throws GLib.Error {
        var folder = new MinimalFolder(
            this.account,
            this.local_folder,
            NONE
        );

        folder.list_email_range_by_id.begin(
            null, int.MAX, RECEIVERS, NONE, null,
            this.async_completion
        );
        var list = assert_collection(
            folder.list_email_range_by_id.end(async_result())
        ).size(2);
        assert_equal(list[0].to[0].address, "test2@example.com");
        assert_equal(list[1].to[0].address, "test1@example.com");

        folder.list_email_range_by_id.begin(
            null, int.MAX, RECEIVERS, OLDEST_TO_NEWEST, null,
            this.async_completion
        );
        list = assert_collection(
            folder.list_email_range_by_id.end(async_result())
        ).size(2);
        assert_equal(list[0].to[0].address, "test1@example.com");
        assert_equal(list[1].to[0].address, "test2@example.com");
    }

    public void list_email_range_by_non_null_id_descending() throws GLib.Error {
        var folder = new MinimalFolder(
            this.account,
            this.local_folder,
            NONE
        );
        var invalid_id = new ImapDB.EmailIdentifier(0, new Imap.UID(0));
        var valid_id1 = new ImapDB.EmailIdentifier(1, new Imap.UID(1));
        var valid_id2 = new ImapDB.EmailIdentifier(2, new Imap.UID(2));

        folder.list_email_range_by_id.begin(
            invalid_id, int.MAX, NONE, NONE, null, this.async_completion
        );
        try {
            folder.list_email_range_by_id.end(async_result());
            assert_not_reached();
        } catch (EngineError.NOT_FOUND err) {
            // all good
        }

        folder.list_email_range_by_id.begin(
            valid_id1, int.MAX, RECEIVERS, NONE, null, this.async_completion
        );
        var list = assert_collection(
            folder.list_email_range_by_id.end(async_result())
        ).is_empty();

        folder.list_email_range_by_id.begin(
            valid_id1, int.MAX, RECEIVERS, INCLUDING_ID, null,
            this.async_completion
        );
        list = assert_collection(
            folder.list_email_range_by_id.end(async_result())
        ).size(1);
        assert_equal(list[0].to[0].address, "test1@example.com");

        folder.list_email_range_by_id.begin(
            valid_id2, int.MAX, RECEIVERS, INCLUDING_ID, null,
            this.async_completion
        );
        list = assert_collection(
            folder.list_email_range_by_id.end(async_result())
        ).size(2);
        assert_equal(list[0].to[0].address, "test2@example.com");
        assert_equal(list[1].to[0].address, "test1@example.com");
    }

    public void list_email_range_by_non_null_id_ascending() throws GLib.Error {
        var folder = new MinimalFolder(
            this.account,
            this.local_folder,
            NONE
        );
        var invalid_id = new ImapDB.EmailIdentifier(0, new Imap.UID(0));
        var valid_id1 = new ImapDB.EmailIdentifier(1, new Imap.UID(1));
        var valid_id2 = new ImapDB.EmailIdentifier(2, new Imap.UID(2));

        folder.list_email_range_by_id.begin(
            invalid_id, int.MAX, NONE, OLDEST_TO_NEWEST, null,
            this.async_completion
        );
        try {
            folder.list_email_range_by_id.end(async_result());
            assert_not_reached();
        } catch (EngineError.NOT_FOUND err) {
            // all good
        }

        folder.list_email_range_by_id.begin(
            valid_id2, int.MAX, RECEIVERS, OLDEST_TO_NEWEST, null,
            this.async_completion
        );
        var list = assert_collection(
            folder.list_email_range_by_id.end(async_result())
        ).is_empty();

        folder.list_email_range_by_id.begin(
            valid_id2, int.MAX, RECEIVERS, INCLUDING_ID | OLDEST_TO_NEWEST, null,
            this.async_completion
        );
        list = assert_collection(
            folder.list_email_range_by_id.end(async_result())
        ).size(1);
        assert_equal(list[0].to[0].address, "test2@example.com");

        folder.list_email_range_by_id.begin(
            valid_id1, int.MAX, RECEIVERS, INCLUDING_ID | OLDEST_TO_NEWEST, null,
            this.async_completion
        );
        list = assert_collection(
            folder.list_email_range_by_id.end(async_result())
        ).size(2);
        assert_equal(list[0].to[0].address, "test1@example.com");
        assert_equal(list[1].to[0].address, "test2@example.com");

        folder.list_email_range_by_id.begin(
            valid_id1, int.MAX, RECEIVERS, OLDEST_TO_NEWEST, null,
            this.async_completion
        );
        list = assert_collection(
            folder.list_email_range_by_id.end(async_result())
        ).size(1);
        assert_equal(list[1].to[0].address, "test2@example.com");

        folder.list_email_range_by_id.begin(
            valid_id1, int.MAX, RECEIVERS, OLDEST_TO_NEWEST | INCLUDING_ID, null,
            this.async_completion
        );
        list = assert_collection(
            folder.list_email_range_by_id.end(async_result())
        ).size(2);
        assert_equal(list[0].to[0].address, "test1@example.com");
        assert_equal(list[1].to[0].address, "test2@example.com");
    }

    public void list_email_range_by_id_partial() throws GLib.Error {
        var folder = new MinimalFolder(
            this.account,
            this.local_folder,
            NONE
        );

        folder.list_email_range_by_id.begin(
            null, int.MAX, NONE, NONE, null,
            this.async_completion
        );
        var list = assert_collection(
            folder.list_email_range_by_id.end(async_result())
        ).size(2);

        folder.list_email_range_by_id.begin(
            null, int.MAX, RECEIVERS, NONE, null,
            this.async_completion
        );
        list = assert_collection(
            folder.list_email_range_by_id.end(async_result())
        ).size(2);

        folder.list_email_range_by_id.begin(
            null, int.MAX, ORIGINATORS, NONE, null,
            this.async_completion
        );
        try {
            folder.list_email_range_by_id.end(async_result());
            assert_not_reached("receivers-fields");
        } catch (EngineError.INCOMPLETE_MESSAGE err) {
            // all good
        }

        folder.list_email_range_by_id.begin(
            null, int.MAX, ORIGINATORS, INCLUDING_PARTIAL, null,
            this.async_completion
        );
        list = assert_collection(
            folder.list_email_range_by_id.end(async_result())
        ).size(2);

        folder.list_email_range_by_id.begin(
            null, int.MAX, ALL, NONE, null,
            this.async_completion
        );
        try {
            folder.list_email_range_by_id.end(async_result());
            assert_not_reached("all-fields");
        } catch (EngineError.INCOMPLETE_MESSAGE err) {
            // all good
        }

        folder.list_email_range_by_id.begin(
            null, int.MAX, ALL, INCLUDING_PARTIAL, null,
            this.async_completion
        );
        list = assert_collection(
            folder.list_email_range_by_id.end(async_result())
        ).size(2);
    }

}
