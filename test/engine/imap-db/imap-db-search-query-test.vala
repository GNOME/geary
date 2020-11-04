/*
 * Copyright © 2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

public class Geary.ImapDB.SearchQueryTest : TestCase {


    private GLib.File? tmp_dir = null;
    private Geary.AccountInformation? config = null;
    private Account? account = null;
    private SnowBall.Stemmer? stemmer = null;


    public SearchQueryTest() {
        base("Geary.ImapDB.SearchQueryTest");
        add_test("email_text_terms", email_text_terms);
        add_test("email_text_terms_stemmed", email_text_terms_stemmed);
        add_test("email_text_terms_specific", email_text_terms_specific);
        add_test("email_flag_terms", email_flag_terms);
    }

    public override void set_up() throws GLib.Error {
        this.tmp_dir = GLib.File.new_for_path(
            GLib.DirUtils.make_tmp("geary-imap-db-search-query-test-XXXXXX")
        );

        this.config = new Geary.AccountInformation(
            "test",
            ServiceProvider.OTHER,
            new Mock.CredentialsMediator(),
            new Geary.RFC822.MailboxAddress(null, "test@example.com")
        );

        this.account = new Account(
            config,
            this.tmp_dir,
            GLib.File.new_for_path(_SOURCE_ROOT_DIR).get_child("sql")
        );
        this.account.open_async.begin(
            null,
            this.async_completion
        );
        this.account.open_async.end(async_result());

        this.stemmer = new SnowBall.Stemmer("english");

        Db.Context.enable_sql_logging = true;
    }

    public override void tear_down() throws GLib.Error {
        Db.Context.enable_sql_logging = false;

        this.stemmer = null;

        this.account.close_async.begin(
            null,
            this.async_completion
        );
        this.account.close_async.end(async_result());
        this.account = null;
        this.config = null;

        delete_file(this.tmp_dir);
        this.tmp_dir = null;
    }

    public void email_text_terms() throws GLib.Error {
        var single_all_term = new_search_query(
            { new Geary.SearchQuery.EmailTextTerm(ALL, EXACT, "test")},
            "test"
        );
        assert_queries(single_all_term);

        var multiple_all_term = new_search_query(
            {
                new Geary.SearchQuery.EmailTextTerm(ALL, EXACT, "foo"),
                new Geary.SearchQuery.EmailTextTerm(ALL, EXACT, "bar")
            },
            "foo bar"
        );
        assert_queries(multiple_all_term);

        var all_to_term = new_search_query(
            {
                new Geary.SearchQuery.EmailTextTerm(ALL, EXACT, "foo"),
                new Geary.SearchQuery.EmailTextTerm(TO, EXACT, "bar")
            },
            "foo to:bar"
        );
        assert_queries(all_to_term);

        var all_to_all_term = new_search_query(
            {
                new Geary.SearchQuery.EmailTextTerm(ALL, EXACT, "foo"),
                new Geary.SearchQuery.EmailTextTerm(TO, EXACT, "bar"),
                new Geary.SearchQuery.EmailTextTerm(ALL, EXACT, "baz")
            },
            "foo to:bar baz"
        );
        assert_queries(all_to_all_term);
    }

    public void email_text_terms_stemmed() throws GLib.Error {
        var single_all_term = new_search_query(
            { new Geary.SearchQuery.EmailTextTerm(ALL, CONSERVATIVE, "universal")},
            "universal"
        );
        assert_queries(single_all_term);

        var multiple_all_term = new_search_query(
            {
                new Geary.SearchQuery.EmailTextTerm(ALL, CONSERVATIVE, "universal"),
                new Geary.SearchQuery.EmailTextTerm(ALL, EXACT, "bar")
            },
            "universal bar"
        );
        assert_queries(multiple_all_term);

        var all_to_term = new_search_query(
            {
                new Geary.SearchQuery.EmailTextTerm(ALL, CONSERVATIVE, "universal"),
                new Geary.SearchQuery.EmailTextTerm(TO, EXACT, "bar")
            },
            "universal to:bar"
        );
        assert_queries(all_to_term);
    }

    public void email_text_terms_specific() throws GLib.Error {
        var single_term = new_search_query(
            { new Geary.SearchQuery.EmailTextTerm(SUBJECT, EXACT, "test")},
            "subject:test"
        );
        assert_queries(single_term);

        var missing_term = new_search_query(
            { new Geary.SearchQuery.EmailTextTerm(SUBJECT, EXACT, "")},
            "subject:"
        );
        assert_queries(missing_term);

        var conflicting_property = new_search_query(
            { new Geary.SearchQuery.EmailTextTerm(ALL, EXACT, "subject:")},
            "subject:"
        );
        assert_queries(conflicting_property);

        var conflicting_property_and_term = new_search_query(
            { new Geary.SearchQuery.EmailTextTerm(SUBJECT, EXACT, "subject:")},
            "subject:subject:"
        );
        assert_queries(conflicting_property_and_term);
    }

    public void email_flag_terms() throws GLib.Error {
        var unread = new_search_query(
            { new Geary.SearchQuery.EmailFlagTerm(Geary.EmailFlags.UNREAD)},
            "is:unread"
        );
        assert_queries(unread);

        var flagged = new_search_query(
            { new Geary.SearchQuery.EmailFlagTerm(Geary.EmailFlags.FLAGGED)},
            "is:flagged"
        );
        assert_queries(flagged);
    }

    private SearchQuery new_search_query(Geary.SearchQuery.Term[] ops, string raw)
        throws GLib.Error {
        return new SearchQuery(
            new Gee.ArrayList<Geary.SearchQuery.Term>.wrap(ops),
            raw,
            this.stemmer
        );
    }

    private void assert_queries(SearchQuery query) throws GLib.Error {
        var search = query.get_search_query(
            this.account.db.get_primary_connection(),
            null,
            null,
            0,
            10,
            null
        );
        search.exec(null);

        var match = query.get_match_query(
            this.account.db.get_primary_connection(),
            ""
        );
        match.exec(null);
    }

}
