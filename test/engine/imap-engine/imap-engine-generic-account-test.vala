/*
 * Copyright 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

public class Geary.ImapEngine.GenericAccountTest : TestCase {


    internal class TestAccount : GenericAccount {

        public TestAccount(AccountInformation config,
                           ImapDB.Account local,
                           Endpoint incoming_remote,
                           Endpoint outgoing_remote) {
            base(config, local, incoming_remote, outgoing_remote);
        }

        protected override MinimalFolder new_folder(ImapDB.Folder local_folder) {
            return new MinimalFolder(
                this,
                local_folder,
                NONE
            );
        }

    }


    private GLib.File? tmp_dir = null;
    private Geary.AccountInformation? config = null;
    private ImapDB.Account? local_account = null;


    public GenericAccountTest() {
        base("Geary.ImapEngine.GenericAccountTest");
        add_test("to_email_identifier", to_email_identifier);
    }

    public override void set_up() throws GLib.Error {
        this.tmp_dir = GLib.File.new_for_path(
            GLib.DirUtils.make_tmp(
                "geary-imap-engine-generic-account-test-XXXXXX"
            )
        );

        this.config = new Geary.AccountInformation(
            "test",
            ServiceProvider.OTHER,
            new Mock.CredentialsMediator(),
            new Geary.RFC822.MailboxAddress(null, "test@example.com")
        );

        this.local_account = new ImapDB.Account(
            config,
            this.tmp_dir,
            GLib.File.new_for_path(_SOURCE_ROOT_DIR).get_child("sql")
        );
        this.local_account.open_async.begin(null, this.async_completion);
        this.local_account.open_async.end(async_result());
    }

    public override void tear_down() throws GLib.Error {
        this.local_account.close_async.begin(null, this.async_completion);
        this.local_account.close_async.end(async_result());
        this.local_account = null;
        this.config = null;

        delete_file(this.tmp_dir);
        this.tmp_dir = null;
    }

    public void to_email_identifier() throws GLib.Error {
        TestAccount test_article = new TestAccount(
            this.config,
            this.local_account,
            new Endpoint(new GLib.NetworkAddress("localhost", 143), NONE, 0),
            new Endpoint(new GLib.NetworkAddress("localhost", 25), NONE, 0)
        );

        assert_non_null(
            test_article.to_email_identifier(
                new GLib.Variant(
                    "(yr)", 'i', new GLib.Variant("(xx)", 1, 2)
                )
            )
        );
        assert_non_null(
            test_article.to_email_identifier(
                new GLib.Variant(
                    "(yr)", 'o', new GLib.Variant("(xx)", 1, 2)
                )
            )
        );
    }

}
