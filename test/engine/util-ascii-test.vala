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
        assert_int(-1, Ascii.index_of("", 'a'));
        assert_int(0, Ascii.index_of("a", 'a'));
        assert_int(0, Ascii.index_of("aa", 'a'));

        assert_int(0, Ascii.index_of("abcabc", 'a'));
        assert_int(1, Ascii.index_of("abcabc", 'b'));
        assert_int(2, Ascii.index_of("abcabc", 'c'));

        assert_int(0, Ascii.index_of("@", '@'));

        assert_int(-1, Ascii.index_of("abc", 'd'));
    }

    public void last_index_of() throws Error {
        assert_int(-1, Ascii.last_index_of("", 'a'));
        assert_int(0, Ascii.last_index_of("a", 'a'));
        assert_int(1, Ascii.last_index_of("aa", 'a'));

        assert_int(3, Ascii.last_index_of("abcabc", 'a'));
        assert_int(4, Ascii.last_index_of("abcabc", 'b'));
        assert_int(5, Ascii.last_index_of("abcabc", 'c'));

        assert_int(0, Ascii.last_index_of("@", '@'));

        assert_int(-1, Ascii.last_index_of("abc", 'd'));
    }

}
