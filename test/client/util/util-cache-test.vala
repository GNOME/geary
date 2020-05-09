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
        assert_equal(test_article.size, 0);

        assert_true(test_article.get_entry(A) == null);
        test_article.set_entry(A, A);
        assert_equal(test_article.get_entry(A), A);

        assert_false(test_article.is_empty);
        assert_equal<uint?>(test_article.size, 1);

        test_article.set_entry(B, B);
        assert_equal(test_article.get_entry(B), B);
        assert_equal<uint?>(test_article.size, 2);

        test_article.set_entry(C, C);
        assert_equal(test_article.get_entry(C), C);
        assert_equal<uint?>(test_article.size, 2);
        assert_true(test_article.get_entry(A) == null);

        test_article.set_entry(D, D);
        assert_equal(test_article.get_entry(D), D);
        assert_equal<uint?>(test_article.size, 2);
        assert_true(test_article.get_entry(B) == null);

        test_article.clear();
        assert_true(test_article.is_empty);
        assert_equal<uint?>(test_article.size, 0);
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

        assert_equal(test_article.get_entry(C), C);
        assert_equal(test_article.get_entry(A), A);
        assert_true(test_article.get_entry(B) == null);
    }

}
