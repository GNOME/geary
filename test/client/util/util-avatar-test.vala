/*
 * Copyright 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

public class Util.Avatar.Test : TestCase {

    public Test() {
        base("UtilAvatarTest");
        add_test("extract_initials", extract_initials);
    }

    public void extract_initials() throws GLib.Error {
        assert_string("A", extract_initials_from_name("aardvark"));
        assert_string("AB", extract_initials_from_name("aardvark baardvark"));
        assert_string("AB", extract_initials_from_name("aardvark  baardvark"));
        assert_string("AC", extract_initials_from_name("aardvark baardvark caardvark"));

        assert_string("A", extract_initials_from_name("!aardvark"));
        assert_string("AB", extract_initials_from_name("aardvark !baardvark"));
        assert_string("AC", extract_initials_from_name("aardvark baardvark !caardvark"));

        assert_string("Ó", extract_initials_from_name("óvári"));

        assert_true(extract_initials_from_name("") == null);
        assert_true(extract_initials_from_name(" ") == null);
        assert_true(extract_initials_from_name("  ") == null);
        assert_true(extract_initials_from_name("!") == null);
        assert_true(extract_initials_from_name("!!") == null);
        assert_true(extract_initials_from_name("! !") == null);
        assert_true(extract_initials_from_name("! !!") == null);
    }

}
