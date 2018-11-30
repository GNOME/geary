/*
 * Copyright 2017 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

class Geary.EngineTest : TestCase {


    private Engine? engine = null;
    private File? tmp = null;
    private File? res = null;


    public EngineTest() {
        base("Geary.EngineTest");
        add_test("add_account", add_account);
        add_test("remove_account", remove_account);
        add_test("re_add_account", re_add_account);
        add_test("create_orphan_account_with_legacy", create_orphan_account_with_legacy);
        add_test("create_orphan_account", create_orphan_account);
    }

    ~EngineTest() {
        // Need this in addition to the code in tear_down in case a
        // test fails
        if (this.tmp != null) {
            try {
                @delete(this.tmp);
            } catch (Error err) {
                print("\nError removing tmp files: %s\n", err.message);
            }
        }
    }

    public override void set_up() throws GLib.Error {
        // XXX this whole thing stinks. We need to be able to test the
        // engine without creating all of these dirs.

        this.tmp = GLib.File.new_for_path(
            GLib.DirUtils.make_tmp("geary-engine-test-XXXXXX")
        );

        this.res = this.tmp.get_child("res");
        this.res.make_directory();

        this.engine = new Engine();
        this.engine.open_async.begin(
            res, null,
            (obj, res) => {
                async_complete(res);
            });
        this.engine.open_async.end(async_result());
    }

	public override void tear_down () {
        try {
            this.res.delete();
            this.tmp.delete();
            this.tmp = null;
        } catch (Error err) {
            assert_not_reached();
        }
	}

    public void add_account() throws GLib.Error {
        AccountInformation info = this.engine.create_orphan_account(
            new MockServiceInformation(),
            new MockServiceInformation()
        );
        assert_false(this.engine.has_account(info.id));

        this.engine.add_account(info);
        assert_true(this.engine.has_account(info.id), "Account not added");

        try {
            this.engine.add_account(info);
            assert_not_reached();
        } catch (GLib.Error err) {
            // expected
        }
    }

    public void remove_account() throws GLib.Error {
        AccountInformation info = this.engine.create_orphan_account(
            new MockServiceInformation(),
            new MockServiceInformation()
        );
        this.engine.add_account(info);
        assert_true(this.engine.has_account(info.id));

        this.engine.remove_account(info);
        assert_false(this.engine.has_account(info.id), "Account not rmoeved");

        // Should not throw an error
        this.engine.remove_account(info);
    }

    public void re_add_account() throws GLib.Error {
        AccountInformation info = this.engine.create_orphan_account(
            new MockServiceInformation(),
            new MockServiceInformation()
        );
        assert_false(this.engine.has_account(info.id));

        this.engine.add_account(info);
        this.engine.remove_account(info);
        this.engine.add_account(info);

        assert_true(this.engine.has_account(info.id));
    }

    public void create_orphan_account() throws Error {
        try {
            AccountInformation info = this.engine.create_orphan_account(
                new MockServiceInformation(),
                new MockServiceInformation()
            );
            assert(info.id == "account_01");
            this.engine.add_account(info);

            info = this.engine.create_orphan_account(
                new MockServiceInformation(),
                new MockServiceInformation()
            );
            assert(info.id == "account_02");
            this.engine.add_account(info);

            info = this.engine.create_orphan_account(
                new MockServiceInformation(),
                new MockServiceInformation()
            );
            assert(info.id == "account_03");
            this.engine.add_account(info);

            info = this.engine.create_orphan_account(
                new MockServiceInformation(),
                new MockServiceInformation()
            );
            assert(info.id == "account_04");
        } catch (Error err) {
            print("\nerr: %s\n", err.message);
            assert_not_reached();
        }
    }

    public void create_orphan_account_with_legacy() throws Error {
        this.engine.add_account(
            new AccountInformation(
                "foo",
                new MockServiceInformation(),
                new MockServiceInformation()
            )
        );

        AccountInformation info = this.engine.create_orphan_account(
            new MockServiceInformation(),
            new MockServiceInformation()
        );
        assert(info.id == "account_01");
        this.engine.add_account(info);

        info = this.engine.create_orphan_account(
            new MockServiceInformation(),
            new MockServiceInformation()
        );
        assert(info.id == "account_02");

        this.engine.add_account(
            new AccountInformation(
                "bar",
                new MockServiceInformation(),
                new MockServiceInformation()
            )
        );

        info = this.engine.create_orphan_account(
            new MockServiceInformation(),
            new MockServiceInformation()
        );
        assert(info.id == "account_02");
    }

    private void delete(File parent) throws Error {
        FileInfo info = parent.query_info(
            "standard::*",
            FileQueryInfoFlags.NOFOLLOW_SYMLINKS
        );

        if (info.get_file_type () == FileType.DIRECTORY) {
            FileEnumerator enumerator = parent.enumerate_children(
                "standard::*",
                FileQueryInfoFlags.NOFOLLOW_SYMLINKS
            );

            info = null;
            while (((info = enumerator.next_file()) != null)) {
                @delete(parent.get_child(info.get_name()));
            }
        }

        parent.delete();
    }

}