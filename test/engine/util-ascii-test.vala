/*
 * Copyright 2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

class Geary.Ascii.Test : TestCase {

    public Test() {
        base("Geary.Ascii.Test");
        add_test("index_of", index_of);
        add_test("last_index_of", last_index_of);
    }

    public void index_of() throws Error {
        assert_equal<int?>(Ascii.index_of("", 'a'), -1);
        assert_equal<int?>(Ascii.index_of("a", 'a'), 0);
        assert_equal<int?>(Ascii.index_of("aa", 'a'), 0);

        assert_equal<int?>(Ascii.index_of("abcabc", 'a'), 0);
        assert_equal<int?>(Ascii.index_of("abcabc", 'b'), 1);
        assert_equal<int?>(Ascii.index_of("abcabc", 'c'), 2);

        assert_equal<int?>(Ascii.index_of("@", '@'), 0);

        assert_equal<int?>(Ascii.index_of("abc", 'd'), -1);
    }

    public void last_index_of() throws Error {
        assert_equal<int?>(Ascii.last_index_of("", 'a'), -1);
        assert_equal<int?>(Ascii.last_index_of("a", 'a'), 0);
        assert_equal<int?>(Ascii.last_index_of("aa", 'a'), 1);

        assert_equal<int?>(Ascii.last_index_of("abcabc", 'a'), 3);
        assert_equal<int?>(Ascii.last_index_of("abcabc", 'b'), 4);
        assert_equal<int?>(Ascii.last_index_of("abcabc", 'c'), 5);

        assert_equal<int?>(Ascii.last_index_of("@", '@'), 0);

        assert_equal<int?>(Ascii.last_index_of("abc", 'd'), -1);
    }

}
