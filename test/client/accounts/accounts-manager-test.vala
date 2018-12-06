/*
 * Copyright 2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

class Accounts.ManagerTest : TestCase {


    private const string TEST_ID = "test";

    private Manager? test = null;
    private Geary.AccountInformation? account = null;
    private Geary.ServiceInformation? service = null;
    private File? tmp = null;


    public ManagerTest() {
        base("AccountManagerTest");
        add_test("create_account", create_account);
        add_test("create_orphan_account", create_orphan_account);
        add_test("create_orphan_account_with_legacy", create_orphan_account_with_legacy);
        add_test("account_config_v1", account_config_v1);
        add_test("account_config_legacy", account_config_legacy);
        add_test("service_config_v1", service_config_v1);
        add_test("service_config_legacy", service_config_legacy);
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

        this.test = new Manager(new GearyApplication(), config, data);

        this.account = new Geary.AccountInformation(
            TEST_ID,
            Geary.ServiceProvider.OTHER,
            new Geary.RFC822.MailboxAddress(null, "test1@example.com")
        );

        this.service = new Geary.ServiceInformation(Geary.Protocol.SMTP, null);
    }

	public override void tear_down() throws GLib.Error {
        this.test = null;
        this.account = null;
        this.service = null;
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
             (obj, res) => { async_complete(res); }
        );
        this.test.create_account.end(async_result());

        assert_int(1, this.test.size, "Account manager size");
        assert_equal(account, this.test.get_account(TEST_ID), "Is not contained");
        assert_true(was_added, "Was not added");
        assert_true(was_enabled, "Was not enabled");
    }

    public void create_orphan_account() throws GLib.Error {
        Geary.AccountInformation account1 = this.test.new_orphan_account(
            Geary.ServiceProvider.OTHER,
            new Geary.RFC822.MailboxAddress(null, "test1@example.com")
        );
        assert(account1.id == "account_01");

        this.test.create_account.begin(
            account1, new GLib.Cancellable(),
            (obj, res) => { async_complete(res); }
        );
        this.test.create_account.end(async_result());

        Geary.AccountInformation account2 = this.test.new_orphan_account(
            Geary.ServiceProvider.OTHER,
            new Geary.RFC822.MailboxAddress(null, "test1@example.com")
        );
        assert(account2.id == "account_02");
    }

    public void create_orphan_account_with_legacy() throws GLib.Error {
        this.test.create_account.begin(
            account, new GLib.Cancellable(),
             (obj, res) => { async_complete(res); }
        );
        this.test.create_account.end(async_result());

        Geary.AccountInformation account1 = this.test.new_orphan_account(
            Geary.ServiceProvider.OTHER,
            new Geary.RFC822.MailboxAddress(null, "test1@example.com")
        );
        assert(account1.id == "account_01");

        this.test.create_account.begin(
            account1, new GLib.Cancellable(),
            (obj, res) => { async_complete(res); }
        );
        this.test.create_account.end(async_result());

        Geary.AccountInformation account2 = this.test.new_orphan_account(
            Geary.ServiceProvider.OTHER,
            new Geary.RFC822.MailboxAddress(null, "test1@example.com")
        );
        assert(account2.id == "account_02");
    }

    public void account_config_v1() throws GLib.Error {
        this.account.email_signature = "blarg";
        this.account.nickname = "test-name";
        this.account.ordinal = 100;
        this.account.prefetch_period_days = 42;
        this.account.save_drafts = false;
        this.account.save_sent_mail = false;
        this.account.use_email_signature = false;
        Accounts.AccountConfigV1 config = new Accounts.AccountConfigV1(false);

        Geary.ConfigFile file =
            new Geary.ConfigFile(this.tmp.get_child("config"));

        config.save(this.account, file);
        Geary.AccountInformation copy = config.load(file, TEST_ID, null, null);

        assert_true(this.account.equal_to(copy));
    }

    public void account_config_legacy() throws GLib.Error {
        this.account.email_signature = "blarg";
        this.account.nickname = "test-name";
        this.account.ordinal = 100;
        this.account.prefetch_period_days = 42;
        this.account.save_drafts = false;
        this.account.save_sent_mail = false;
        this.account.use_email_signature = false;
        Accounts.AccountConfigLegacy config =
            new Accounts.AccountConfigLegacy();

        Geary.ConfigFile file =
            new Geary.ConfigFile(this.tmp.get_child("config"));

        config.save(this.account, file);
        Geary.AccountInformation copy = config.load(file, TEST_ID, null, null);

        assert_true(this.account.equal_to(copy));
    }

    public void service_config_v1() throws GLib.Error {
        this.service.host = "blarg";
        this.service.port = 1234;
        this.service.transport_security = Geary.TlsNegotiationMethod.NONE;
        this.service.smtp_credentials_source = Geary.SmtpCredentials.CUSTOM;
        this.service.credentials = new Geary.Credentials(
            Geary.Credentials.Method.PASSWORD, "testerson"
        );
        Accounts.ServiceConfigV1 config = new Accounts.ServiceConfigV1();
        Geary.ConfigFile file =
            new Geary.ConfigFile(this.tmp.get_child("config"));

        config.save(this.account, this.service, file);
        Geary.ServiceInformation copy = config.load(
            file, this.account, this.service.protocol, null
        );

        assert_true(this.service.equal_to(copy));
    }

    public void service_config_legacy() throws GLib.Error {
        this.service.host = "blarg";
        this.service.port = 1234;
        this.service.transport_security = Geary.TlsNegotiationMethod.NONE;
        this.service.smtp_credentials_source = Geary.SmtpCredentials.CUSTOM;
        this.service.credentials = new Geary.Credentials(
            Geary.Credentials.Method.PASSWORD, "testerson"
        );
        Accounts.ServiceConfigLegacy config = new Accounts.ServiceConfigLegacy();
        Geary.ConfigFile file =
            new Geary.ConfigFile(this.tmp.get_child("config"));

        config.save(this.account, this.service, file);
        Geary.ServiceInformation copy = config.load(
            file, this.account, this.service.protocol, null
        );

        assert_true(this.service.equal_to(copy));
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
