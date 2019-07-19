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
        assert_string("A", extract_initials_from_name("aardvark"), "basic");
        assert_string("AB", extract_initials_from_name("aardvark baardvark"), "basic");
        assert_string("AB", extract_initials_from_name("aardvark  baardvark"), "basic");
        assert_string("AC", extract_initials_from_name("aardvark baardvark caardvark"), "basic");

        assert_string("A", extract_initials_from_name("!aardvark"), "extra sym");
        assert_string("AB", extract_initials_from_name("aardvark !baardvark"), "extra sym");
        assert_string("AC", extract_initials_from_name("aardvark baardvark !caardvark"), "extra sym");

        assert_true(extract_initials_from_name("") == null, "edge");
        assert_true(extract_initials_from_name(" ") == null, "edge");
        assert_true(extract_initials_from_name("  ") == null, "edge");
        assert_true(extract_initials_from_name("!") == null, "edge");
        assert_true(extract_initials_from_name("!!") == null, "edge");
        assert_true(extract_initials_from_name("! !") == null, "edge");
        assert_true(extract_initials_from_name("! !!") == null, "edge");
    }

}
