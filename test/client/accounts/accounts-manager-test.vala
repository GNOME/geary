/*
 * Copyright 2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

class Accounts.ManagerTest : TestCase {


    private const string TEST_ID = "test";

    private Manager? test = null;
    private Geary.CredentialsMediator? mediator = null;
    private Geary.AccountInformation? account = null;
    private Geary.RFC822.MailboxAddress primary_mailbox;
    private File? tmp = null;


    public ManagerTest() {
        base("AccountManagerTest");
        add_test("create_account", create_account);
        add_test("create_orphan_account", create_orphan_account);
        add_test(
            "create_orphan_account_with_legacy",
            create_orphan_account_with_legacy
        );
        add_test(
            "create_orphan_account_with_existing_dirs",
            create_orphan_account_with_existing_dirs
        );
        add_test("account_config_v1", account_config_v1);
        add_test("account_config_legacy", account_config_legacy);
        add_test("service_config_v1", service_config_v1);
        add_test("service_config_legacy", service_config_legacy);
    }

    public override void set_up() throws GLib.Error {
        // XXX this whole thing stinks. We need to be able to test the
        // engine without creating all of these dirs.

        this.tmp = GLib.File.new_for_path(
            GLib.DirUtils.make_tmp("accounts-manager-test-XXXXXX")
        );

        this.primary_mailbox = new Geary.RFC822.MailboxAddress(
            null, "test1@example.com"
        );

        this.mediator = new Mock.CredentialsMediator();
        this.account = new Geary.AccountInformation(
            TEST_ID,
            Geary.ServiceProvider.OTHER,
            this.mediator,
            this.primary_mailbox
        );
        this.test = new Manager(this.mediator, this.tmp, this.tmp);
    }

    public override void tear_down() throws GLib.Error {
        this.account = null;
        this.mediator = null;
        this.test = null;
        this.primary_mailbox = null;
        @delete(this.tmp);
    }

    public void create_account() throws GLib.Error {
        bool was_added = false;
        bool was_enabled = false;

        this.test.account_added.connect((added, status) => {
                was_added = (added == account);
                was_enabled = (status == Manager.Status.ENABLED);
            });

        this.test.create_account.begin(
            account, new GLib.Cancellable(),
             this.async_completion
        );
        this.test.create_account.end(async_result());

        assert_equal<int?>(this.test.size, 1, "Account manager size");
        assert_equal(this.test.get_account(TEST_ID), account, "Is not contained");
        assert_true(was_added, "Was not added");
        assert_true(was_enabled, "Was not enabled");
    }

    public void create_orphan_account() throws GLib.Error {
        this.test.new_orphan_account.begin(
            Geary.ServiceProvider.OTHER, this.primary_mailbox, null,
            this.async_completion
        );
        Geary.AccountInformation account1 =
            this.test.new_orphan_account.end(async_result());
        assert(account1.id == "account_01");

        this.test.create_account.begin(
            account1, new GLib.Cancellable(),
            this.async_completion
        );
        this.test.create_account.end(async_result());

        this.test.new_orphan_account.begin(
            Geary.ServiceProvider.OTHER, this.primary_mailbox, null,
            this.async_completion
        );
        Geary.AccountInformation account2 =
            this.test.new_orphan_account.end(async_result());
        assert(account2.id == "account_02");
    }

    public void create_orphan_account_with_legacy() throws GLib.Error {
        this.test.create_account.begin(
            account, new GLib.Cancellable(),
            this.async_completion
        );
        this.test.create_account.end(async_result());

        this.test.new_orphan_account.begin(
            Geary.ServiceProvider.OTHER, this.primary_mailbox, null,
            this.async_completion
        );
        Geary.AccountInformation account1 =
            this.test.new_orphan_account.end(async_result());
        assert(account1.id == "account_01");

        this.test.create_account.begin(
            account1, new GLib.Cancellable(),
            this.async_completion
        );
        this.test.create_account.end(async_result());

        this.test.new_orphan_account.begin(
            Geary.ServiceProvider.OTHER, this.primary_mailbox, null,
            this.async_completion
        );
        Geary.AccountInformation account2 =
            this.test.new_orphan_account.end(async_result());
        assert(account2.id == "account_02");
    }

    public void create_orphan_account_with_existing_dirs() throws GLib.Error {
        GLib.File existing = this.test.config_dir.get_child("account_01");
        existing.make_directory();
        existing = this.test.data_dir.get_child("account_02");
        existing.make_directory();

        this.test.new_orphan_account.begin(
            Geary.ServiceProvider.OTHER, this.primary_mailbox, null,
            this.async_completion
        );
        Geary.AccountInformation account =
            this.test.new_orphan_account.end(async_result());
        assert(account.id == "account_03");
    }

    public void account_config_v1() throws GLib.Error {
        this.account.label = "test-name";
        this.account.ordinal = 100;
        this.account.prefetch_period_days = 42;
        this.account.save_drafts = false;
        this.account.save_sent = false;
        this.account.signature = "blarg";
        this.account.use_signature = false;

        Geary.ConfigFile file =
            new Geary.ConfigFile(this.tmp.get_child("config.ini"));

        Accounts.AccountConfigV1 config = new Accounts.AccountConfigV1(false);
        config.save(this.account, file);

        Geary.AccountInformation copy = config.load(
            file, TEST_ID, this.mediator, null, null
        );

        assert_true(this.account.equal_to(copy));
    }

    public void account_config_legacy() throws GLib.Error {
        this.account.label = "test-name";
        this.account.ordinal = 100;
        this.account.prefetch_period_days = 42;
        this.account.save_drafts = false;
        this.account.save_sent = false;
        this.account.signature = "blarg";
        this.account.use_signature = false;
        Accounts.AccountConfigLegacy config =
            new Accounts.AccountConfigLegacy();

        Geary.ConfigFile file =
            new Geary.ConfigFile(this.tmp.get_child("config.ini"));

        config.save(this.account, file);
        Geary.AccountInformation copy = config.load(
            file, TEST_ID, this.mediator, null, null
        );

        assert_true(this.account.equal_to(copy));
    }

    public void service_config_v1() throws GLib.Error {
        // take a copy before updating the service info so we don't
        // also copy the test data
        Geary.AccountInformation copy = new Geary.AccountInformation.copy(
            this.account
        );

        this.account.outgoing.host = "blarg";
        this.account.outgoing.port = 1234;
        this.account.outgoing.transport_security = Geary.TlsNegotiationMethod.NONE;
        this.account.outgoing.credentials = new Geary.Credentials(
            Geary.Credentials.Method.PASSWORD, "testerson"
        );
        this.account.outgoing.credentials_requirement =
            Geary.Credentials.Requirement.NONE;
        Accounts.ServiceConfigV1 config = new Accounts.ServiceConfigV1();
        Geary.ConfigFile file =
            new Geary.ConfigFile(this.tmp.get_child("config.ini"));

        config.save(this.account, this.account.outgoing, file);
        config.load(file, copy, copy.outgoing);

        assert_true(this.account.outgoing.equal_to(copy.outgoing));
    }

    public void service_config_legacy() throws GLib.Error {
        // take a copy before updating the service info so we don't
        // also copy the test data
        Geary.AccountInformation copy = new Geary.AccountInformation.copy(
            this.account
        );

        this.account.outgoing.host = "blarg";
        this.account.outgoing.port = 1234;
        this.account.outgoing.transport_security = Geary.TlsNegotiationMethod.NONE;
        this.account.outgoing.credentials = new Geary.Credentials(
            Geary.Credentials.Method.PASSWORD, "testerson"
        );
        this.account.outgoing.credentials_requirement =
            Geary.Credentials.Requirement.NONE;
        Accounts.ServiceConfigLegacy config = new Accounts.ServiceConfigLegacy();
        Geary.ConfigFile file =
            new Geary.ConfigFile(this.tmp.get_child("config.ini"));

        config.save(this.account, this.account.outgoing, file);
        config.load(file, copy, copy.outgoing);

        assert_true(this.account.outgoing.equal_to(copy.outgoing));
    }

    private void delete(File parent) throws GLib.Error {
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
