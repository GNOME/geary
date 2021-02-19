/*
 * Copyright 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

internal class Geary.ImapEngine.GenericAccountTest : AccountBasedTest {


    public GenericAccountTest() {
        base("Geary.ImapEngine.GenericAccountTest");
        add_test("to_email_identifier", to_email_identifier);
        add_test("get_email_by_id", get_email_by_id);
        add_test("get_email_by_id_partial", get_email_by_id_partial);
        add_test("get_multiple_email_by_id", get_multiple_email_by_id);
        add_test(
            "get_multiple_email_by_id_partial", get_multiple_email_by_id_partial
        );
    }

    public override void set_up() throws GLib.Error {
        base.set_up();

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
    }

    public void to_email_identifier() throws GLib.Error {
        var test_article = new_test_account();

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

    public void get_email_by_id() throws GLib.Error {
        var account = new_test_account();
        var invalid_id = new ImapDB.EmailIdentifier(0, new Imap.UID(0));
        var valid_id = new ImapDB.EmailIdentifier(1, new Imap.UID(1));

        account.get_email_by_id.begin(
            invalid_id, ALL, NONE, null, this.async_completion
        );
        try {
            account.get_email_by_id.end(async_result());
            assert_not_reached();
        } catch (EngineError.NOT_FOUND err) {
            // all good
        }

        account.get_email_by_id.begin(
            valid_id, RECEIVERS, NONE, null, this.async_completion
        );
        var email = account.get_email_by_id.end(async_result());
        assert_true(email.id.equal_to(valid_id));
        assert_non_null(email.to);
        assert_equal<int?>(email.to.size, 1);
        assert_equal(email.to[0].address, "test1@example.com");

        account.get_email_by_id.begin(
            valid_id, ALL, NONE, null, this.async_completion
        );
        try {
            account.get_email_by_id.end(async_result());
            assert_not_reached();
        } catch (EngineError.INCOMPLETE_MESSAGE err) {
            // all good
        }
    }

    public void get_email_by_id_partial() throws GLib.Error {
        var account = new_test_account();
        var valid_id1 = new ImapDB.EmailIdentifier(1, new Imap.UID(1));
        var valid_id2 = new ImapDB.EmailIdentifier(1, new Imap.UID(2));

        // Get an email that actually has all requested flags

        account.get_email_by_id.begin(
            valid_id2,
            ORIGINATORS|RECEIVERS,
            INCLUDING_PARTIAL,
            null,
            this.async_completion
        );
        var complete = account.get_email_by_id.end(async_result());
        assert_true(complete.id.equal_to(valid_id2));

        // Get an  email missing requested flags

        account.get_email_by_id.begin(
            valid_id1,
            ORIGINATORS|RECEIVERS,
            INCLUDING_PARTIAL,
            null,
            this.async_completion
        );
        var incomplete = account.get_email_by_id.end(async_result());
        assert_true(incomplete.id.equal_to(valid_id1));

    }

    public void get_multiple_email_by_id() throws GLib.Error {
        var account = new_test_account();
        var invalid_id = new ImapDB.EmailIdentifier(0, new Imap.UID(0));
        var valid_id = new ImapDB.EmailIdentifier(1, new Imap.UID(1));

        account.get_multiple_email_by_id.begin(
            Collection.single(invalid_id), ALL, NONE, null, this.async_completion
        );
        try {
            account.get_multiple_email_by_id.end(async_result());
            assert_not_reached();
        } catch (EngineError.NOT_FOUND err) {
            // all good
        }

        account.get_multiple_email_by_id.begin(
            Collection.single(valid_id), RECEIVERS, NONE, null, this.async_completion
        );
        var email = assert_collection(
            account.get_multiple_email_by_id.end(async_result())
        ).size(1)[0];
        assert_true(email.id.equal_to(valid_id));
        assert_non_null(email.to);
        assert_equal<int?>(email.to.size, 1);
        assert_equal(email.to[0].address, "test1@example.com");

        account.get_multiple_email_by_id.begin(
            Collection.single(valid_id), ALL, NONE, null, this.async_completion
        );
        try {
            account.get_multiple_email_by_id.end(async_result());
            assert_not_reached();
        } catch (EngineError.INCOMPLETE_MESSAGE err) {
            // all good
        }
    }

    public void get_multiple_email_by_id_partial() throws GLib.Error {
        var account = new_test_account();
        var valid_id1 = new ImapDB.EmailIdentifier(1, new Imap.UID(1));
        var valid_id2 = new ImapDB.EmailIdentifier(2, new Imap.UID(2));

        // get an email that does fulfil all fields

        account.get_multiple_email_by_id.begin(
            Collection.single(valid_id2),
            ORIGINATORS|RECEIVERS,
            INCLUDING_PARTIAL,
            null,
            this.async_completion
        );
        var complete = assert_collection(
            account.get_multiple_email_by_id.end(async_result())
        ).size(1)[0];
        assert_true(complete.id.equal_to(valid_id2));

        // get an email that does not fulfil all fields

        account.get_multiple_email_by_id.begin(
            Collection.single(valid_id1),
            ORIGINATORS|RECEIVERS,
            INCLUDING_PARTIAL,
            null,
            this.async_completion
        );
        var incomplete = assert_collection(
            account.get_multiple_email_by_id.end(async_result())
        ).size(1)[0];
        assert_true(incomplete.id.equal_to(valid_id1));


        // get a mix of both

        account.get_multiple_email_by_id.begin(
            new Gee.ArrayList<EmailIdentifier>.wrap({valid_id1,valid_id2}),
            ORIGINATORS|RECEIVERS,
            INCLUDING_PARTIAL,
            null,
            this.async_completion
        );
        assert_collection(
            account.get_multiple_email_by_id.end(async_result())
        ).size(2);
    }

}
