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
        var test_article = new SearchExpressionFactory(this.config, this.account);

        var empty = test_article.parse_query("");
        assert_true(empty is Geary.SearchQuery.AndOperator);
        var and = empty as Geary.SearchQuery.AndOperator;
        assert_true(and.get_operands().is_empty);
    }

    public void plain_search_terms() throws GLib.Error {
        var test_article = new SearchExpressionFactory(this.config, this.account);

        var simple1 = test_article.parse_query("hello");
        assert_true(simple1 is Geary.SearchQuery.TextOperator);
        var text1 = simple1 as Geary.SearchQuery.TextOperator;
        assert_true(text1.target == ALL);
        assert_true(text1.matching_strategy == CONSERVATIVE);
        assert_equal(text1.term, "hello");

        var simple2 = test_article.parse_query("h");
        assert_true(simple2 is Geary.SearchQuery.TextOperator);
        var text2 = simple2 as Geary.SearchQuery.TextOperator;
        assert_equal(text2.term, "h");

        var simple3 = test_article.parse_query(" h");
        assert_true(simple3 is Geary.SearchQuery.TextOperator);
        var text3 = simple3 as Geary.SearchQuery.TextOperator;
        assert_equal(text3.term, "h");

        var simple4 = test_article.parse_query("h ");
        assert_true(simple4 is Geary.SearchQuery.TextOperator);
        var text4 = simple4 as Geary.SearchQuery.TextOperator;
        assert_equal(text4.term, "h");
    }

    public void continuation_search_terms() throws GLib.Error {
        var test_article = new SearchExpressionFactory(this.config, this.account);

        var simple1 = test_article.parse_query("hello-there");
        assert_true(simple1 is Geary.SearchQuery.TextOperator);
        var text1 = simple1 as Geary.SearchQuery.TextOperator;
        assert_equal("hello-there", text1.term);

        var simple2 = test_article.parse_query("hello-");
        assert_true(simple2 is Geary.SearchQuery.TextOperator);
        var text2 = simple2 as Geary.SearchQuery.TextOperator;
        assert_equal(text2.term, "hello-");

        var simple3 = test_article.parse_query("test@example.com");
        assert_true(simple3 is Geary.SearchQuery.TextOperator);
        var text3 = simple3 as Geary.SearchQuery.TextOperator;
        assert_equal(text3.term, "test@example.com");
    }

    public void i18n_search_terms() throws GLib.Error {
        var test_article = new SearchExpressionFactory(
            this.config, this.account
        );
        test_article.language = Pango.Language.from_string("th");

        var multiple = test_article.parse_query("ภาษาไทย");
        assert_true(multiple is Geary.SearchQuery.AndOperator);
        var and = multiple as Geary.SearchQuery.AndOperator;

        var operands = and.get_operands().to_array();
        assert_equal<int?>(operands.length, 2);
        assert_true(operands[0] is Geary.SearchQuery.TextOperator);
        assert_true(operands[1] is Geary.SearchQuery.TextOperator);
        assert_equal(
            ((Geary.SearchQuery.TextOperator) operands[0]).term,
            "ภาษา"
        );
        assert_equal(
            ((Geary.SearchQuery.TextOperator) operands[1]).term,
            "ไทย"
        );
    }

    public void multiple_search_terms() throws GLib.Error {
        var test_article = new SearchExpressionFactory(this.config, this.account);

        var multiple = test_article.parse_query("hello there");
        assert_true(multiple is Geary.SearchQuery.AndOperator);
        var and = multiple as Geary.SearchQuery.AndOperator;

        var operands = and.get_operands().to_array();
        assert_equal<int?>(operands.length, 2);
        assert_true(operands[0] is Geary.SearchQuery.TextOperator);
        assert_true(operands[1] is Geary.SearchQuery.TextOperator);
        assert_equal(
            ((Geary.SearchQuery.TextOperator) operands[0]).term,
            "hello"
        );
        assert_equal(
            ((Geary.SearchQuery.TextOperator) operands[1]).term,
            "there"
        );
    }

    public void quoted_search_terms() throws GLib.Error {
        var test_article = new SearchExpressionFactory(this.config, this.account);

        var simple1 = test_article.parse_query("\"hello\"");
        assert_true(simple1 is Geary.SearchQuery.TextOperator);
        var text1 = simple1 as Geary.SearchQuery.TextOperator;
        assert_true(text1.target == ALL);
        assert_true(text1.matching_strategy == EXACT);
        assert_equal(text1.term, "hello");

        var simple2 = test_article.parse_query("\"h\"");
        assert_true(simple2 is Geary.SearchQuery.TextOperator);
        var text2 = simple2 as Geary.SearchQuery.TextOperator;
        assert_equal(text2.term, "h");

        var simple3 = test_article.parse_query(" \"h\"");
        assert_true(simple3 is Geary.SearchQuery.TextOperator);
        var text3 = simple3 as Geary.SearchQuery.TextOperator;
        assert_equal(text3.term, "h");

        var simple4 = test_article.parse_query("\"h");
        assert_true(simple4 is Geary.SearchQuery.TextOperator);
        var text4 = simple4 as Geary.SearchQuery.TextOperator;
        assert_equal(text4.term, "h");

        var simple5 = test_article.parse_query("\"h\" ");
        assert_true(simple5 is Geary.SearchQuery.TextOperator);
        var text5 = simple5 as Geary.SearchQuery.TextOperator;
        assert_equal(text5.term, "h");

        var simple6 = test_article.parse_query("\"hello there\"");
        assert_true(simple6 is Geary.SearchQuery.TextOperator);
        var text6 = simple6 as Geary.SearchQuery.TextOperator;
        assert_equal(text6.term, "hello there");
    }

    public void text_op_terms() throws GLib.Error {
        var test_article = new SearchExpressionFactory(this.config, this.account);

        var simple_body = test_article.parse_query("body:hello");
        assert_true(simple_body is Geary.SearchQuery.TextOperator);
        var text_body = simple_body as Geary.SearchQuery.TextOperator;
        assert_true(text_body.target == BODY);
        assert_true(text_body.matching_strategy == CONSERVATIVE);
        assert_equal(text_body.term, "hello");

        var simple_body_quoted = test_article.parse_query("body:\"hello\"");
        assert_true(simple_body_quoted is Geary.SearchQuery.TextOperator);
        var text_body_quoted = simple_body_quoted as Geary.SearchQuery.TextOperator;
        assert_true(text_body_quoted.target == BODY);
        assert_true(text_body_quoted.matching_strategy == EXACT);
        assert_equal(text_body_quoted.term, "hello");

        var simple_attach_name = test_article.parse_query("attachment:hello");
        assert_true(simple_attach_name is Geary.SearchQuery.TextOperator);
        var text_attch_name = simple_attach_name as Geary.SearchQuery.TextOperator;
        assert_true(text_attch_name.target == ATTACHMENT_NAME);

        var simple_bcc = test_article.parse_query("bcc:hello");
        assert_true(simple_bcc is Geary.SearchQuery.TextOperator);
        var text_bcc = simple_bcc as Geary.SearchQuery.TextOperator;
        assert_true(text_bcc.target == BCC);

        var simple_cc = test_article.parse_query("cc:hello");
        assert_true(simple_cc is Geary.SearchQuery.TextOperator);
        var text_cc = simple_cc as Geary.SearchQuery.TextOperator;
        assert_true(text_cc.target == CC);

        var simple_from = test_article.parse_query("from:hello");
        assert_true(simple_from is Geary.SearchQuery.TextOperator);
        var text_from = simple_from as Geary.SearchQuery.TextOperator;
        assert_true(text_from.target == FROM);

        var simple_subject = test_article.parse_query("subject:hello");
        assert_true(simple_subject is Geary.SearchQuery.TextOperator);
        var text_subject = simple_subject as Geary.SearchQuery.TextOperator;
        assert_true(text_subject.target == SUBJECT);

        var simple_to = test_article.parse_query("to:hello");
        assert_true(simple_to is Geary.SearchQuery.TextOperator);
        var text_to = simple_to as Geary.SearchQuery.TextOperator;
        assert_true(text_to.target == TO);
    }

    public void text_op_single_me_terms() throws GLib.Error {
        var test_article = new SearchExpressionFactory(this.config, this.account);

        var simple_to = test_article.parse_query("to:me");
        assert_true(simple_to is Geary.SearchQuery.TextOperator);
        var text_to = simple_to as Geary.SearchQuery.TextOperator;
        assert_true(text_to.target == TO);
        assert_true(text_to.matching_strategy == EXACT);
        assert_equal(text_to.term, "test@example.com");

        var simple_cc = test_article.parse_query("cc:me");
        assert_true(simple_cc is Geary.SearchQuery.TextOperator);
        var text_cc = simple_cc as Geary.SearchQuery.TextOperator;
        assert_true(text_cc.target == CC);
        assert_true(text_cc.matching_strategy == EXACT);
        assert_equal(text_cc.term, "test@example.com");

        var simple_bcc = test_article.parse_query("bcc:me");
        assert_true(simple_bcc is Geary.SearchQuery.TextOperator);
        var text_bcc = simple_bcc as Geary.SearchQuery.TextOperator;
        assert_true(text_bcc.target == BCC);
        assert_true(text_bcc.matching_strategy == EXACT);
        assert_equal(text_bcc.term, "test@example.com");

        var simple_from = test_article.parse_query("from:me");
        assert_true(simple_from is Geary.SearchQuery.TextOperator);
        var text_from = simple_from as Geary.SearchQuery.TextOperator;
        assert_true(text_from.target == FROM);
        assert_true(text_from.matching_strategy == EXACT);
        assert_equal(text_from.term, "test@example.com");
    }

    public void text_op_multiple_me_terms() throws GLib.Error {
        this.account.append_sender(
            new Geary.RFC822.MailboxAddress("test2", "test2@example.com")
        );
        var test_article = new SearchExpressionFactory(this.config, this.account);

        var to = test_article.parse_query("to:me");
        assert_true(to is Geary.SearchQuery.OrOperator);
        var or = to as Geary.SearchQuery.OrOperator;
        var operands = or.get_operands().to_array();
        assert_equal<int?>(operands.length, 2);
        assert_true(operands[0] is Geary.SearchQuery.TextOperator);
        assert_true(operands[1] is Geary.SearchQuery.TextOperator);
        assert_equal(
            ((Geary.SearchQuery.TextOperator) operands[0]).term,
            "test@example.com"
        );
        assert_equal(
            ((Geary.SearchQuery.TextOperator) operands[1]).term,
            "test2@example.com"
        );
    }

    public void boolean_op_terms() throws GLib.Error {
        var test_article = new SearchExpressionFactory(this.config, this.account);

        var simple_unread = test_article.parse_query("is:unread");
        assert_true(simple_unread is Geary.SearchQuery.BooleanOperator);
        var bool_unread = simple_unread as Geary.SearchQuery.BooleanOperator;
        assert_true(bool_unread.target == IS_UNREAD);
        assert_true(bool_unread.value);

        var simple_read = test_article.parse_query("is:read");
        assert_true(simple_read is Geary.SearchQuery.BooleanOperator);
        var bool_read = simple_read as Geary.SearchQuery.BooleanOperator;
        assert_true(bool_read.target == IS_UNREAD);
        assert_false(bool_read.value);

        var simple_starred = test_article.parse_query("is:starred");
        assert_true(simple_starred is Geary.SearchQuery.BooleanOperator);
        var bool_starred = simple_starred as Geary.SearchQuery.BooleanOperator;
        assert_true(bool_starred.target == IS_FLAGGED);
        assert_true(bool_starred.value);
    }

    public void invalid_op_terms() throws GLib.Error {
        var test_article = new SearchExpressionFactory(this.config, this.account);

        var simple1 = test_article.parse_query("body:");
        assert_true(simple1 is Geary.SearchQuery.TextOperator);
        var text1 = simple1 as Geary.SearchQuery.TextOperator;
        assert_true(text1.target == ALL);
        assert_true(text1.matching_strategy == CONSERVATIVE);
        assert_equal(text1.term, "body");

        var simple2 = test_article.parse_query("blarg:");
        assert_true(simple2 is Geary.SearchQuery.TextOperator);
        var text2 = simple2 as Geary.SearchQuery.TextOperator;
        assert_true(text2.target == ALL);
        assert_true(text2.matching_strategy == CONSERVATIVE);
        assert_equal(text2.term, "blarg");

        var simple3 = test_article.parse_query("blarg:hello");
        assert_true(simple3 is Geary.SearchQuery.AndOperator);
        var and = simple3 as Geary.SearchQuery.AndOperator;

        var operands = and.get_operands().to_array();
        assert_equal<int?>(operands.length, 2);
        assert_true(operands[0] is Geary.SearchQuery.TextOperator);
        assert_true(operands[1] is Geary.SearchQuery.TextOperator);
        assert_equal(
            ((Geary.SearchQuery.TextOperator) operands[0]).term,
            "blarg"
        );
        assert_equal(
            ((Geary.SearchQuery.TextOperator) operands[1]).term,
            "hello"
        );
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
