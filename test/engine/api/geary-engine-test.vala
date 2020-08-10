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
    private Geary.AccountInformation? account = null;


    public EngineTest() {
        base("Geary.EngineTest");
        add_test("add_account", add_account);
        add_test("remove_account", remove_account);
        add_test("re_add_account", re_add_account);
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

        this.engine = new Engine(res);

        this.account = new AccountInformation(
            "test",
            ServiceProvider.OTHER,
            new Mock.CredentialsMediator(),
            new RFC822.MailboxAddress(null, "test1@example.com")
        );
        this.account.set_account_directories(this.tmp, this.tmp);
    }

    public override void tear_down() throws GLib.Error {
        this.account = null;
        this.res.delete();
        this.tmp.delete();
        this.tmp = null;
    }

    public void add_account() throws GLib.Error {
        assert_false(this.engine.has_account(this.account));

        this.engine.add_account(this.account);
        assert_true(this.engine.has_account(this.account), "Account not added");

        try {
            this.engine.add_account(this.account);
            assert_not_reached();
        } catch (GLib.Error err) {
            // expected
        }
    }

    public void remove_account() throws GLib.Error {
        this.engine.add_account(this.account);
        assert_true(this.engine.has_account(this.account));

        this.engine.remove_account(this.account);
        assert_false(this.engine.has_account(this.account), "Account not removed");

        try {
            this.engine.remove_account(this.account);
            assert_not_reached();
        } catch (GLib.Error err) {
            // expected
        }
    }

    public void re_add_account() throws GLib.Error {
        assert_false(this.engine.has_account(this.account));

        this.engine.add_account(this.account);
        this.engine.remove_account(this.account);
        this.engine.add_account(this.account);

        assert_true(this.engine.has_account(this.account));
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