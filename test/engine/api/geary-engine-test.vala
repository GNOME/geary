/*
 * Copyright 2017 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

class Geary.EngineTest : Gee.TestCase {

    private Engine? engine = null;
    private File? tmp = null;
    private File? config = null;
    private File? data = null;
    private File? res = null;

    public EngineTest() {
        base("Geary.EngineTest");
        add_test("create_orphan_account", create_orphan_account);
        add_test("create_orphan_account_with_legacy", create_orphan_account_with_legacy);
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

    public override void set_up() {
        // XXX this whole thing stinks. We need to be able to test the
        // engine without creating all of these dirs.

        try {
            this.tmp = File.new_for_path(Environment.get_tmp_dir()).get_child("geary-test");
            this.tmp.make_directory();

            this.config = this.tmp.get_child("config");
            this.config.make_directory();

            this.data = this.tmp.get_child("data");
            this.data.make_directory();

            this.res = this.tmp.get_child("res");
            this.res.make_directory();

            this.engine = new Engine();
            this.engine.open_async.begin(
                config, data, res, null, null,
                (obj, res) => {
                    async_complete(res);
                });
            this.engine.open_async.end(async_result());
        } catch (Error err) {
            assert_not_reached();
        }
    }

	public override void tear_down () {
        try {
            this.res.delete();
            this.data.delete();
            this.config.delete();
            this.tmp.delete();
            this.tmp = null;
        } catch (Error err) {
            assert_not_reached();
        }
	}

    public void create_orphan_account() {
        try {
            AccountInformation info = this.engine.create_orphan_account();
            assert(info.id == "account_01");
            this.engine.add_account(info, true);

            info = this.engine.create_orphan_account();
            assert(info.id == "account_02");
            this.engine.add_account(info, true);

            info = this.engine.create_orphan_account();
            assert(info.id == "account_03");
            this.engine.add_account(info, true);

            info = this.engine.create_orphan_account();
            assert(info.id == "account_04");
        } catch (Error err) {
            print("\nerr: %s\n", err.message);
            assert_not_reached();
        }
    }

    public void create_orphan_account_with_legacy() {
        try {
            this.engine.add_account(
                new AccountInformation("foo", this.config, this.data),
                true
            );

             AccountInformation info = this.engine.create_orphan_account();
            assert(info.id == "account_01");
            this.engine.add_account(info, true);

            assert(this.engine.create_orphan_account().id == "account_02");

            this.engine.add_account(
                new AccountInformation("bar", this.config, this.data),
                true
            );

            assert(this.engine.create_orphan_account().id == "account_02");
        } catch (Error err) {
            print("\nerr: %s\n", err.message);
            assert_not_reached();
        }
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