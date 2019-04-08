/*
 * Copyright 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

public class Util.Cache.Test : TestCase {

    public Test() {
        base("UtilCacheTest");
        add_test("lru_insertion", lru_insertion);
        add_test("lru_eviction", lru_eviction);
    }

    public void lru_insertion() throws GLib.Error {
        const string A = "a";
        const string B = "b";
        const string C = "c";
        const string D = "d";

        Lru<string> test_article = new Lru<string>(2);

        assert_true(test_article.is_empty);
        assert_uint(0, test_article.size);

        assert_true(test_article.get_entry(A) == null);
        test_article.set_entry(A, A);
        assert_string(A, test_article.get_entry(A));

        assert_false(test_article.is_empty);
        assert_uint(1, test_article.size);

        test_article.set_entry(B, B);
        assert_string(B, test_article.get_entry(B));
        assert_uint(2, test_article.size);

        test_article.set_entry(C, C);
        assert_string(C, test_article.get_entry(C));
        assert_uint(2, test_article.size);
        assert_true(test_article.get_entry(A) == null);

        test_article.set_entry(D, D);
        assert_string(D, test_article.get_entry(D));
        assert_uint(2, test_article.size);
        assert_true(test_article.get_entry(B) == null);

        test_article.clear();
        assert_true(test_article.is_empty);
        assert_uint(0, test_article.size);
    }

    public void lru_eviction() throws GLib.Error {
        const string A = "a";
        const string B = "b";
        const string C = "c";

        Lru<string> test_article = new Lru<string>(2);

        test_article.set_entry(A, A);
        test_article.set_entry(B, B);

        test_article.get_entry(A);
        test_article.set_entry(C, C);

        assert_string(C, test_article.get_entry(C));
        assert_string(A, test_article.get_entry(A));
        assert_true(test_article.get_entry(B) == null);
    }

}
