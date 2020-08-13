/*
 * Copyright 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */


class Geary.ImapDB.AccountTest : TestCase {


    private GLib.File? tmp_dir = null;
    private Geary.AccountInformation? config = null;
    private Account? account = null;
    private FolderRoot? root = null;


    public AccountTest() {
        base("Geary.ImapDB.AccountTest");
        add_test("create_base_folder", create_base_folder);
        add_test("create_child_folder", create_child_folder);
        add_test("list_folders", list_folders);
        add_test("delete_folder", delete_folder);
        add_test("delete_folder_with_child", delete_folder_with_child);
        add_test("delete_nonexistent_folder", delete_nonexistent_folder);
        add_test("fetch_base_folder", fetch_base_folder);
        add_test("fetch_child_folder", fetch_child_folder);
        add_test("fetch_nonexistent_folder", fetch_nonexistent_folder);
        add_test("list_local_email", list_local_email);
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

        this.root = new FolderRoot("#test", false);
    }

    public override void tear_down() throws GLib.Error {
        this.root = null;
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

    public void create_base_folder() throws GLib.Error {
        Imap.Folder folder = new Imap.Folder(
            this.root.get_child("test"),
            new Imap.FolderProperties.selectable(
                new Imap.MailboxAttributes(
                    Gee.Collection.empty<Geary.Imap.MailboxAttribute>()
                ),
                new Imap.StatusData(
                    new Imap.MailboxSpecifier("test"),
                    10, // total
                    9, // recent
                    new Imap.UID(8),
                    new Imap.UIDValidity(7),
                    6 //unseen
                ),
                new Imap.Capabilities.empty(0)
            )
        );

        this.account.clone_folder_async.begin(
            folder,
            null,
            this.async_completion
        );
        this.account.clone_folder_async.end(async_result());

        Geary.Db.Result result = this.account.db.query(
            "SELECT * FROM FolderTable;"
        );
        assert_false(result.finished, "Folder not created");
        assert_equal(result.string_for("name"), "test", "Folder name");
        assert_true(result.is_null_for("parent_id"), "Folder parent");
        assert_false(result.next(), "Multiple rows inserted");
    }

    public void create_child_folder() throws GLib.Error {
        this.account.db.exec(
            "INSERT INTO FolderTable (id, name) VALUES (1, 'test');"
        );

        Imap.Folder folder = new Imap.Folder(
            this.root.get_child("test").get_child("child"),
            new Imap.FolderProperties.selectable(
                new Imap.MailboxAttributes(
                    Gee.Collection.empty<Geary.Imap.MailboxAttribute>()
                ),
                new Imap.StatusData(
                    new Imap.MailboxSpecifier("test>child"),
                    10, // total
                    9, // recent
                    new Imap.UID(8),
                    new Imap.UIDValidity(7),
                    6 //unseen
                ),
                new Imap.Capabilities.empty(0)
            )
        );

        this.account.clone_folder_async.begin(
            folder,
            null,
            this.async_completion
        );
        this.account.clone_folder_async.end(async_result());

        Geary.Db.Result result = this.account.db.query(
            "SELECT * FROM FolderTable WHERE id != 1;"
        );
        assert_false(result.finished, "Folder not created");
        assert_equal(result.string_for("name"), "child", "Folder name");
        assert_equal<int?>(result.int_for("parent_id"), 1, "Folder parent");
        assert_false(result.next(), "Multiple rows inserted");
    }

    public void list_folders() throws GLib.Error {
        this.account.db.exec("""
            INSERT INTO FolderTable (id, name, parent_id)
            VALUES
                (1, 'test1', null),
                (2, 'test2', 1),
                (3, 'test3', 2);
        """);

        this.account.list_folders_async.begin(
            this.account.imap_folder_root,
            null,
            this.async_completion
        );
        Gee.Collection<Geary.ImapDB.Folder> result =
            this.account.list_folders_async.end(async_result());

        Folder test1 = traverse(result).first();
        assert_equal<int?>(result.size, 1, "Base folder not listed");
        assert_equal(test1.get_path().name, "test1", "Base folder name");

        this.account.list_folders_async.begin(
            test1.get_path(),
            null,
            this.async_completion
        );
        result = this.account.list_folders_async.end(async_result());

        Folder test2 = traverse(result).first();
        assert_equal<int?>(result.size, 1, "Child folder not listed");
        assert_equal(test2.get_path().name, "test2", "Child folder name");

        this.account.list_folders_async.begin(
            test2.get_path(),
            null,
            this.async_completion
        );
        result = this.account.list_folders_async.end(async_result());

        Folder test3 = traverse(result).first();
        assert_equal<int?>(result.size, 1, "Grandchild folder not listed");
        assert_equal(test3.get_path().name, "test3", "Grandchild folder name");
    }

    public void delete_folder() throws GLib.Error {
        this.account.db.exec("""
            INSERT INTO FolderTable (id, name, parent_id)
            VALUES
                (1, 'test1', null),
                (2, 'test2', 1);
        """);

        this.account.delete_folder_async.begin(
            this.root.get_child("test1").get_child("test2"),
            null,
            this.async_completion
        );
        this.account.delete_folder_async.end(async_result());

        this.account.delete_folder_async.begin(
            this.root.get_child("test1"),
            null,
            this.async_completion
        );
        this.account.delete_folder_async.end(async_result());
    }

    public void delete_folder_with_child() throws GLib.Error {
        this.account.db.exec("""
            INSERT INTO FolderTable (id, name, parent_id)
            VALUES
                (1, 'test1', null),
                (2, 'test2', 1);
        """);

        this.account.delete_folder_async.begin(
            this.root.get_child("test1"),
            null,
            this.async_completion
        );
        try {
            this.account.delete_folder_async.end(async_result());
            assert_not_reached();
        } catch (GLib.Error err) {
            assert_error(new ImapError.NOT_SUPPORTED(""), err);
        }
    }

    public void delete_nonexistent_folder() throws GLib.Error {
        this.account.db.exec("""
            INSERT INTO FolderTable (id, name, parent_id)
            VALUES
                (1, 'test1', null),
                (2, 'test2', 1);
        """);

        this.account.delete_folder_async.begin(
            this.root.get_child("test3"),
            null,
            this.async_completion
        );
        try {
            this.account.delete_folder_async.end(async_result());
            assert_not_reached();
        } catch (GLib.Error err) {
            assert_error(new EngineError.NOT_FOUND(""), err);
        }
    }

    public void fetch_base_folder() throws GLib.Error {
        this.account.db.exec("""
            INSERT INTO FolderTable (id, name, parent_id)
            VALUES
                (1, 'test1', null),
                (2, 'test2', 1);
        """);

        this.account.fetch_folder_async.begin(
            this.root.get_child("test1"),
            null,
            this.async_completion
        );

        Folder? result = this.account.fetch_folder_async.end(async_result());
        assert_non_null(result);
        assert_equal(result.get_path().name, "test1");
    }

    public void fetch_child_folder() throws GLib.Error {
        this.account.db.exec("""
            INSERT INTO FolderTable (id, name, parent_id)
            VALUES
                (1, 'test1', null),
                (2, 'test2', 1);
        """);

        this.account.fetch_folder_async.begin(
            this.root.get_child("test1").get_child("test2"),
            null,
            this.async_completion
        );

        Folder? result = this.account.fetch_folder_async.end(async_result());
        assert_non_null(result);
        assert_equal(result.get_path().name, "test2");
    }

    public void fetch_nonexistent_folder() throws GLib.Error {
        this.account.db.exec("""
            INSERT INTO FolderTable (id, name, parent_id)
            VALUES
                (1, 'test1', null),
                (2, 'test2', 1);
        """);

        this.account.fetch_folder_async.begin(
            this.root.get_child("test3"),
            null,
            this.async_completion
        );
        try {
            this.account.fetch_folder_async.end(async_result());
            assert_not_reached();
        } catch (GLib.Error err) {
            assert_error(new EngineError.NOT_FOUND(""), err);
        }
    }

    public void list_local_email() throws GLib.Error {
        Email.Field fixture_fields = Email.Field.RECEIVERS;
        string fixture_to = "test1@example.com";
        this.account.db.exec(
            "INSERT INTO MessageTable (id, fields, to_field) " +
            "VALUES (1, %d, '%s');".printf(fixture_fields, fixture_to)
        );
        this.account.db.exec(
            "INSERT INTO MessageTable (id, fields, to_field) " +
            "VALUES (2, %d, '%s');".printf(fixture_fields, fixture_to)
        );

        this.account.list_email.begin(
            iterate_array<Geary.ImapDB.EmailIdentifier>({
                    new EmailIdentifier(1, null),
                    new EmailIdentifier(2, null)
                }).to_linked_list(),
            Email.Field.RECEIVERS,
            null,
            this.async_completion
        );
        Gee.List<Email> result = this.account.list_email.end(
            async_result()
        );

        assert_equal<int?>(result.size, 2, "Not enough email listed");
        assert_true(new EmailIdentifier(1, null).equal_to(result[0].id));
        assert_true(new EmailIdentifier(2, null).equal_to(result[1].id));

        this.account.list_email.begin(
            Collection.single(new EmailIdentifier(3, null)),
            Email.Field.RECEIVERS,
            null,
            this.async_completion
        );
        try {
            this.account.list_email.end(async_result());
            assert_not_reached();
        } catch (EngineError.NOT_FOUND error) {
            // All good
        }

        this.account.list_email.begin(
            Collection.single(new EmailIdentifier(1, null)),
            Email.Field.BODY,
            null,
            this.async_completion
        );
        try {
            this.account.list_email.end(async_result());
            assert_not_reached();
        } catch (EngineError.INCOMPLETE_MESSAGE error) {
            // All good
        }
    }

}
