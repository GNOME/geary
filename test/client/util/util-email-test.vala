/*
 * Copyright 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

public class Util.Email.Test : TestCase {


    private Application.Configuration? config = null;
    private Geary.AccountInformation? account = null;


    public Test() {
        base("Util.Email.Test");
        add_test("null_originator", null_originator);
        add_test("from_originator", from_originator);
        add_test("sender_originator", sender_originator);
        add_test("reply_to_originator", reply_to_originator);
        add_test("reply_to_via_originator", reply_to_via_originator);
        add_test("plain_via_originator", plain_via_originator);
        add_test("empty_search_query", empty_search_query);
        add_test("plain_search_terms", plain_search_terms);
        add_test("continuation_search_terms", continuation_search_terms);
        add_test("i18n_search_terms", i18n_search_terms);
        add_test("multiple_search_terms", multiple_search_terms);
        add_test("quoted_search_terms", quoted_search_terms);
        add_test("text_op_terms", text_op_terms);
        add_test("text_op_single_me_terms", text_op_single_me_terms);
        add_test("text_op_multiple_me_terms", text_op_multiple_me_terms);
        add_test("boolean_op_terms", boolean_op_terms);
        add_test("invalid_op_terms", invalid_op_terms);
    }

    public override void set_up() {
        this.config = new Application.Configuration(Application.Client.SCHEMA_ID);
        this.account = new Geary.AccountInformation(
            "test",
            OTHER,
            new Mock.CredentialsMediator(),
            new Geary.RFC822.MailboxAddress("test", "test@example.com")
        );
    }

    public override void tear_down() {
        this.config = null;
        this.account = null;
    }

    public void null_originator() throws GLib.Error {
        Geary.RFC822.MailboxAddress? originator = get_primary_originator(
            new_email(null, null, null)
        );

        assert_null(originator);
    }

    public void from_originator() throws GLib.Error {
        Geary.RFC822.MailboxAddress? originator = get_primary_originator(
            new_email(
                new Geary.RFC822.MailboxAddress("from", "from@example.com"),
                new Geary.RFC822.MailboxAddress("sender", "sender@example.com"),
                new Geary.RFC822.MailboxAddress("reply-to", "reply-to@example.com")
            )
        );

        assert_non_null(originator);
        assert_equal(originator.name, "from");
        assert_equal(originator.address, "from@example.com");
    }

    public void sender_originator() throws GLib.Error {
        Geary.RFC822.MailboxAddress? originator = get_primary_originator(
            new_email(
                null,
                new Geary.RFC822.MailboxAddress("sender", "sender@example.com"),
                new Geary.RFC822.MailboxAddress("reply-to", "reply-to@example.com")
            )
        );

        assert_non_null(originator);
        assert_equal(originator.name, "sender");
        assert_equal(originator.address, "sender@example.com");
    }

    public void reply_to_originator() throws GLib.Error {
        Geary.RFC822.MailboxAddress? originator = get_primary_originator(
            new_email(
                null,
                null,
                new Geary.RFC822.MailboxAddress("reply-to", "reply-to@example.com")
            )
        );

        assert_non_null(originator);
        assert_equal(originator.name, "reply-to");
        assert_equal(originator.address, "reply-to@example.com");
    }

    public void reply_to_via_originator() throws GLib.Error {
        Geary.RFC822.MailboxAddress? originator = get_primary_originator(
            new_email(
                new Geary.RFC822.MailboxAddress("test via bot", "bot@example.com"),
                null,
                new Geary.RFC822.MailboxAddress("test", "test@example.com")
            )
        );

        assert_non_null(originator);
        assert_equal(originator.name, "test");
        assert_equal(originator.address, "test@example.com");
    }

    public void plain_via_originator() throws GLib.Error {
        Geary.RFC822.MailboxAddress? originator = get_primary_originator(
            new_email(
                new Geary.RFC822.MailboxAddress("test via bot", "bot@example.com"),
                null,
                null
            )
        );

        assert_non_null(originator);
        assert_equal(originator.name, "test");
        assert_equal(originator.address, "bot@example.com");
    }

    public void empty_search_query() throws GLib.Error {
        var test_article = new SearchExpressionFactory(
            this.config.get_search_strategy(), this.account
        );
        assert_collection(test_article.parse_query("")).is_empty();
    }

    public void plain_search_terms() throws GLib.Error {
        var test_article = new SearchExpressionFactory(
            this.config.get_search_strategy(), this.account
        );

        var simple1 = test_article.parse_query("hello");
        assert_collection(simple1).size(1);
        assert_true(simple1[0] is Geary.SearchQuery.EmailTextTerm);
        var text1 = simple1[0] as Geary.SearchQuery.EmailTextTerm;
        assert_true(text1.target == ALL);
        assert_true(text1.matching_strategy == CONSERVATIVE);
        assert_collection(text1.terms).size(1).contains("hello");

        var simple2 = test_article.parse_query("h");
        assert_collection(simple2).size(1);
        assert_true(simple2[0] is Geary.SearchQuery.EmailTextTerm);
        var text2 = simple2[0] as Geary.SearchQuery.EmailTextTerm;
        assert_collection(text2.terms).size(1).contains("h");

        var simple3 = test_article.parse_query(" h");
        assert_collection(simple3).size(1);
        assert_true(simple3[0] is Geary.SearchQuery.EmailTextTerm);
        var text3 = simple3[0] as Geary.SearchQuery.EmailTextTerm;
        assert_collection(text3.terms).size(1).contains("h");

        var simple4 = test_article.parse_query("h ");
        assert_collection(simple4).size(1);
        assert_true(simple4[0] is Geary.SearchQuery.EmailTextTerm);
        var text4 = simple4[0] as Geary.SearchQuery.EmailTextTerm;
        assert_collection(text4.terms).size(1).contains("h");
    }

    public void continuation_search_terms() throws GLib.Error {
        var test_article = new SearchExpressionFactory(
            this.config.get_search_strategy(),
            this.account
        );

        var simple1 = test_article.parse_query("hello-there");
        assert_collection(simple1).size(1);
        assert_true(simple1[0] is Geary.SearchQuery.EmailTextTerm);
        var text1 = simple1[0] as Geary.SearchQuery.EmailTextTerm;
        assert_collection(text1.terms).size(1).contains("hello-there");

        var simple2 = test_article.parse_query("hello-");
        assert_collection(simple2).size(1);
        assert_true(simple2[0] is Geary.SearchQuery.EmailTextTerm);
        var text2 = simple2[0] as Geary.SearchQuery.EmailTextTerm;
        assert_collection(text2.terms).size(1).contains("hello-");

        var simple3 = test_article.parse_query("test@example.com");
        assert_collection(simple2).size(1);
        assert_true(simple3[0] is Geary.SearchQuery.EmailTextTerm);
        var text3 = simple3[0] as Geary.SearchQuery.EmailTextTerm;
        assert_collection(text3.terms).size(1).contains("test@example.com");
    }

    public void i18n_search_terms() throws GLib.Error {
        var test_article = new SearchExpressionFactory(
            this.config.get_search_strategy(),
            this.account
        );

        var thai = test_article.parse_query("ภาษาไทย");
        assert_collection(thai).size(2);
        assert_true(thai[0] is Geary.SearchQuery.EmailTextTerm);
        assert_true(thai[1] is Geary.SearchQuery.EmailTextTerm);
        assert_collection(
            ((Geary.SearchQuery.EmailTextTerm) thai[0]).terms
        ).size(1).contains("ภาษา");
        assert_collection(
            ((Geary.SearchQuery.EmailTextTerm) thai[1]).terms
        ).size(1).contains("ไทย");

        var chinese = test_article.parse_query("男子去");
        assert_collection(chinese).size(2);
        assert_true(chinese[0] is Geary.SearchQuery.EmailTextTerm);
        assert_true(chinese[1] is Geary.SearchQuery.EmailTextTerm);
        assert_collection(
            ((Geary.SearchQuery.EmailTextTerm) chinese[0]).terms
        ).size(1).contains("男子");
        assert_collection(
            ((Geary.SearchQuery.EmailTextTerm) chinese[1]).terms
        ).size(1).contains("去");
    }

    public void multiple_search_terms() throws GLib.Error {
        var test_article = new SearchExpressionFactory(
            this.config.get_search_strategy(), this.account
        );

        var multiple = test_article.parse_query("hello there");
        assert_collection(multiple).size(2);
        assert_true(multiple[0] is Geary.SearchQuery.EmailTextTerm);
        assert_true(multiple[1] is Geary.SearchQuery.EmailTextTerm);
        assert_collection(
            ((Geary.SearchQuery.EmailTextTerm) multiple[0]).terms
        ).size(1).contains("hello");
        assert_collection(
            ((Geary.SearchQuery.EmailTextTerm) multiple[1]).terms
        ).size(1).contains("there");
    }

    public void quoted_search_terms() throws GLib.Error {
        var test_article = new SearchExpressionFactory(
            this.config.get_search_strategy(), this.account
        );

        var simple1 = test_article.parse_query("\"hello\"");
        assert_collection(simple1).size(1);
        assert_true(simple1[0] is Geary.SearchQuery.EmailTextTerm);
        var text1 = simple1[0] as Geary.SearchQuery.EmailTextTerm;
        assert_true(text1.target == ALL);
        assert_true(text1.matching_strategy == EXACT);
        assert_collection(text1.terms).size(1).contains("hello");

        var simple2 = test_article.parse_query("\"h\"");
        assert_collection(simple2).size(1);
        assert_true(simple2[0] is Geary.SearchQuery.EmailTextTerm);
        var text2 = simple2[0] as Geary.SearchQuery.EmailTextTerm;
        assert_collection(text2.terms).size(1).contains("h");

        var simple3 = test_article.parse_query(" \"h\"");
        assert_collection(simple3).size(1);
        assert_true(simple3[0] is Geary.SearchQuery.EmailTextTerm);
        var text3 = simple3[0] as Geary.SearchQuery.EmailTextTerm;
        assert_collection(text3.terms).size(1).contains("h");

        var simple4 = test_article.parse_query("\"h");
        assert_collection(simple4).size(1);
        assert_true(simple4[0] is Geary.SearchQuery.EmailTextTerm);
        var text4 = simple4[0] as Geary.SearchQuery.EmailTextTerm;
        assert_collection(text4.terms).size(1).contains("h");

        var simple5 = test_article.parse_query("\"h\" ");
        assert_collection(simple5).size(1);
        assert_true(simple5[0] is Geary.SearchQuery.EmailTextTerm);
        var text5 = simple5[0] as Geary.SearchQuery.EmailTextTerm;
        assert_collection(text5.terms).size(1).contains("h");

        var simple6 = test_article.parse_query("\"hello there\"");
        assert_collection(simple6).size(1);
        assert_true(simple6[0] is Geary.SearchQuery.EmailTextTerm);
        var text6 = simple6[0] as Geary.SearchQuery.EmailTextTerm;
        assert_collection(text6.terms).size(1).contains("hello there");
    }

    public void text_op_terms() throws GLib.Error {
        var test_article = new SearchExpressionFactory(
            this.config.get_search_strategy(), this.account
        );

        var simple_body = test_article.parse_query("body:hello");
        assert_collection(simple_body).size(1);
        assert_true(simple_body[0] is Geary.SearchQuery.EmailTextTerm, "type");
        var text_body = simple_body[0] as Geary.SearchQuery.EmailTextTerm;
        assert_true(text_body.target == BODY, "target");
        assert_true(text_body.matching_strategy == CONSERVATIVE, "strategy");
        assert_collection(text_body.terms).size(1).contains("hello");

        var simple_body_quoted = test_article.parse_query("body:\"hello\"");
        assert_collection(simple_body_quoted).size(1);
        assert_true(simple_body_quoted[0] is Geary.SearchQuery.EmailTextTerm);
        var text_body_quoted = simple_body_quoted[0] as Geary.SearchQuery.EmailTextTerm;
        assert_true(text_body_quoted.target == BODY);
        assert_true(text_body_quoted.matching_strategy == EXACT);
        assert_collection(text_body_quoted.terms).size(1).contains("hello");

        var simple_attach_name = test_article.parse_query("attachment:hello");
        assert_collection(simple_attach_name).size(1);
        assert_true(simple_attach_name[0] is Geary.SearchQuery.EmailTextTerm);
        var text_attch_name = simple_attach_name[0] as Geary.SearchQuery.EmailTextTerm;
        assert_true(text_attch_name.target == ATTACHMENT_NAME);

        var simple_bcc = test_article.parse_query("bcc:hello");
        assert_collection(simple_bcc).size(1);
        assert_true(simple_bcc[0] is Geary.SearchQuery.EmailTextTerm);
        var text_bcc = simple_bcc[0] as Geary.SearchQuery.EmailTextTerm;
        assert_true(text_bcc.target == BCC);

        var simple_cc = test_article.parse_query("cc:hello");
        assert_collection(simple_cc).size(1);
        assert_true(simple_cc[0] is Geary.SearchQuery.EmailTextTerm);
        var text_cc = simple_cc[0] as Geary.SearchQuery.EmailTextTerm;
        assert_true(text_cc.target == CC);

        var simple_from = test_article.parse_query("from:hello");
        assert_collection(simple_from).size(1);
        assert_true(simple_from[0] is Geary.SearchQuery.EmailTextTerm);
        var text_from = simple_from[0] as Geary.SearchQuery.EmailTextTerm;
        assert_true(text_from.target == FROM);

        var simple_subject = test_article.parse_query("subject:hello");
        assert_collection(simple_subject).size(1);
        assert_true(simple_subject[0] is Geary.SearchQuery.EmailTextTerm);
        var text_subject = simple_subject[0] as Geary.SearchQuery.EmailTextTerm;
        assert_true(text_subject.target == SUBJECT);

        var simple_to = test_article.parse_query("to:hello");
        assert_collection(simple_to).size(1);
        assert_true(simple_to[0] is Geary.SearchQuery.EmailTextTerm);
        var text_to = simple_to[0] as Geary.SearchQuery.EmailTextTerm;
        assert_true(text_to.target == TO);
    }

    public void text_op_single_me_terms() throws GLib.Error {
        var test_article = new SearchExpressionFactory(
            this.config.get_search_strategy(), this.account
        );

        var simple_to = test_article.parse_query("to:me");
        assert_collection(simple_to).size(1);
        assert_true(simple_to[0] is Geary.SearchQuery.EmailTextTerm);
        var text_to = simple_to[0] as Geary.SearchQuery.EmailTextTerm;
        assert_true(text_to.target == TO);
        assert_true(text_to.matching_strategy == EXACT);
        assert_collection(text_to.terms).size(1).contains("test@example.com");

        var simple_cc = test_article.parse_query("cc:me");
        assert_collection(simple_cc).size(1);
        assert_true(simple_cc[0] is Geary.SearchQuery.EmailTextTerm);
        var text_cc = simple_cc[0] as Geary.SearchQuery.EmailTextTerm;
        assert_true(text_cc.target == CC);
        assert_true(text_cc.matching_strategy == EXACT);
        assert_collection(text_cc.terms).size(1).contains("test@example.com");

        var simple_bcc = test_article.parse_query("bcc:me");
        assert_collection(simple_bcc).size(1);
        assert_true(simple_bcc[0] is Geary.SearchQuery.EmailTextTerm);
        var text_bcc = simple_bcc[0] as Geary.SearchQuery.EmailTextTerm;
        assert_true(text_bcc.target == BCC);
        assert_true(text_bcc.matching_strategy == EXACT);
        assert_collection(text_bcc.terms).size(1).contains("test@example.com");

        var simple_from = test_article.parse_query("from:me");
        assert_collection(simple_from).size(1);
        assert_true(simple_from[0] is Geary.SearchQuery.EmailTextTerm);
        var text_from = simple_from[0] as Geary.SearchQuery.EmailTextTerm;
        assert_true(text_from.target == FROM);
        assert_true(text_from.matching_strategy == EXACT);
        assert_collection(text_from.terms).size(1).contains("test@example.com");
    }

    public void text_op_multiple_me_terms() throws GLib.Error {
        this.account.append_sender(
            new Geary.RFC822.MailboxAddress("test2", "test2@example.com")
        );
        var test_article = new SearchExpressionFactory(
            this.config.get_search_strategy(), this.account
        );

        var to = test_article.parse_query("to:me");
        assert_collection(to).size(1);
        assert_true(to[0] is Geary.SearchQuery.EmailTextTerm);
        var text_to = to[0] as Geary.SearchQuery.EmailTextTerm;
        assert_true(text_to.target == TO);
        assert_true(text_to.matching_strategy == EXACT);
        assert_collection(text_to.terms).size(2).contains(
            "test@example.com"
        ).contains(
            "test@example.com"
        );
    }

    public void boolean_op_terms() throws GLib.Error {
        var test_article = new SearchExpressionFactory(
            this.config.get_search_strategy(), this.account
        );

        var simple_unread = test_article.parse_query("is:unread");
        assert_true(simple_unread[0] is Geary.SearchQuery.EmailFlagTerm);
        var bool_unread = simple_unread[0] as Geary.SearchQuery.EmailFlagTerm;
        assert_true(
            bool_unread.value.equal_to(Geary.EmailFlags.UNREAD), "unread flag"
        );
        assert_false(bool_unread.is_negated, "unread negated");

        var simple_read = test_article.parse_query("is:read");
        assert_true(simple_read[0] is Geary.SearchQuery.EmailFlagTerm);
        var bool_read = simple_read[0] as Geary.SearchQuery.EmailFlagTerm;
        assert_true(
            bool_read.value.equal_to(Geary.EmailFlags.UNREAD), "read flag"
        );
        assert_true(bool_read.is_negated, "read negated");

        var simple_starred = test_article.parse_query("is:starred");
        assert_true(simple_starred[0] is Geary.SearchQuery.EmailFlagTerm);
        var bool_starred = simple_starred[0] as Geary.SearchQuery.EmailFlagTerm;
        assert_true(
            bool_starred.value.equal_to(Geary.EmailFlags.FLAGGED), "starred flag"
        );
        assert_false(bool_starred.is_negated, "starred negated");
    }

    public void invalid_op_terms() throws GLib.Error {
        var test_article = new SearchExpressionFactory(
            this.config.get_search_strategy(), this.account
        );

        var simple1 = test_article.parse_query("body:");
        assert_collection(simple1).size(1);
        assert_true(simple1[0] is Geary.SearchQuery.EmailTextTerm);
        var text1 = simple1[0] as Geary.SearchQuery.EmailTextTerm;
        assert_true(text1.target == ALL);
        assert_true(text1.matching_strategy == CONSERVATIVE);
        assert_collection(text1.terms).size(1).contains("body:");

        var simple2 = test_article.parse_query("blarg:");
        assert_collection(simple2).size(1);
        assert_true(simple2[0] is Geary.SearchQuery.EmailTextTerm);
        var text2 = simple2[0] as Geary.SearchQuery.EmailTextTerm;
        assert_true(text2.target == ALL);
        assert_true(text2.matching_strategy == CONSERVATIVE);
        assert_collection(text2.terms).size(1).contains("blarg:");

        var simple3 = test_article.parse_query("blarg:hello");
        assert_collection(simple3).size(1);
        assert_true(simple3[0] is Geary.SearchQuery.EmailTextTerm);
        var text3 = simple3[0] as Geary.SearchQuery.EmailTextTerm;
        assert_true(text3.target == ALL);
        assert_true(text3.matching_strategy == CONSERVATIVE);
        assert_collection(text3.terms).size(1).contains("blarg:hello");
    }

    private Geary.Email new_email(Geary.RFC822.MailboxAddress? from,
                                  Geary.RFC822.MailboxAddress? sender,
                                  Geary.RFC822.MailboxAddress? reply_to)
        throws GLib.Error {
        Geary.Email email = new Geary.Email(new Mock.EmailIdentifer(1));
        email.set_originators(
            from != null
            ? new Geary.RFC822.MailboxAddresses(Geary.Collection.single(from))
            : null,
            sender,
            reply_to != null
            ? new Geary.RFC822.MailboxAddresses(Geary.Collection.single(reply_to))
            : null
        );
        return email;
    }

}
