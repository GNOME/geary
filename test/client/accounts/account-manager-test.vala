/*
 * Copyright 2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

class AccountManagerTest : TestCase {


    private AccountManager? test = null;
    private File? tmp = null;


    public AccountManagerTest() {
        base("AccountManagerTest");
        add_test("create_account", create_account);
        add_test("create_orphan_account", create_orphan_account);
        add_test("create_orphan_account_with_legacy", create_orphan_account_with_legacy);
    }

    public override void set_up() throws GLib.Error {
        // XXX this whole thing stinks. We need to be able to test the
        // engine without creating all of these dirs.

        this.tmp = GLib.File.new_for_path(
            GLib.DirUtils.make_tmp("geary-engine-test-XXXXXX")
        );

        GLib.File config = this.tmp.get_child("config");
        config.make_directory();

        GLib.File data = this.tmp.get_child("data");
        data.make_directory();

        this.test = new AccountManager(new GearyApplication(), config, data);
    }

	public override void tear_down() throws GLib.Error {
        this.test = null;
        @delete(this.tmp);
	}

    public void create_account() throws GLib.Error {
        const string ID = "test";
        Geary.AccountInformation account = new Geary.AccountInformation(
            ID,
            Geary.ServiceProvider.OTHER,
            new Geary.MockServiceInformation(),
            new Geary.MockServiceInformation()
        );
        bool was_added = false;
        bool was_enabled = false;

        this.test.account_added.connect((added, status) => {
                was_added = (added == account);
                was_enabled = (status == AccountManager.Status.ENABLED);
            });

        this.test.create_account.begin(
            account, new GLib.Cancellable(),
             (obj, res) => { async_complete(res); }
        );
        this.test.create_account.end(async_result());

        assert_int(1, this.test.size, "Account manager size");
        assert_equal(account, this.test.get_account(ID), "Is not contained");
        assert_true(was_added, "Was not added");
        assert_true(was_enabled, "Was not enabled");
    }

    public void create_orphan_account() throws GLib.Error {
        Geary.AccountInformation account1 = this.test.new_orphan_account(
            Geary.ServiceProvider.OTHER,
            new Geary.MockServiceInformation(),
            new Geary.MockServiceInformation()
        );
        assert(account1.id == "account_01");

        this.test.create_account.begin(
            account1, new GLib.Cancellable(),
            (obj, res) => { async_complete(res); }
        );
        this.test.create_account.end(async_result());

        Geary.AccountInformation account2 = this.test.new_orphan_account(
            Geary.ServiceProvider.OTHER,
            new Geary.MockServiceInformation(),
            new Geary.MockServiceInformation()
        );
        assert(account2.id == "account_02");
    }

    public void create_orphan_account_with_legacy() throws GLib.Error {
        const string ID = "test";
        Geary.AccountInformation account = new Geary.AccountInformation(
            ID,
            Geary.ServiceProvider.OTHER,
            new Geary.MockServiceInformation(),
            new Geary.MockServiceInformation()
        );

        this.test.create_account.begin(
            account, new GLib.Cancellable(),
             (obj, res) => { async_complete(res); }
        );
        this.test.create_account.end(async_result());

        Geary.AccountInformation account1 = this.test.new_orphan_account(
            Geary.ServiceProvider.OTHER,
            new Geary.MockServiceInformation(),
            new Geary.MockServiceInformation()
        );
        assert(account1.id == "account_01");

        this.test.create_account.begin(
            account1, new GLib.Cancellable(),
            (obj, res) => { async_complete(res); }
        );
        this.test.create_account.end(async_result());

        Geary.AccountInformation account2 = this.test.new_orphan_account(
            Geary.ServiceProvider.OTHER,
            new Geary.MockServiceInformation(),
            new Geary.MockServiceInformation()
        );
        assert(account2.id == "account_02");
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
