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

}
