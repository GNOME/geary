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
        assert_equal(extract_initials_from_name("aardvark"), "A");
        assert_equal(extract_initials_from_name("aardvark baardvark"), "AB");
        assert_equal(extract_initials_from_name("aardvark  baardvark"), "AB");
        assert_equal(
            extract_initials_from_name("aardvark baardvark caardvark"), "AC"
        );

        assert_equal(
            extract_initials_from_name("!aardvark"), "A"
        );
        assert_equal(
            extract_initials_from_name("aardvark !baardvark"), "AB"
        );
        assert_equal(
            extract_initials_from_name("aardvark baardvark !caardvark"), "AC"
        );

        assert_equal(extract_initials_from_name("óvári"), "Ó");

        assert_null(extract_initials_from_name(""));
        assert_null(extract_initials_from_name(" "));
        assert_null(extract_initials_from_name("  "));
        assert_null(extract_initials_from_name("!"));
        assert_null(extract_initials_from_name("!!"));
        assert_null(extract_initials_from_name("! !"));
        assert_null(extract_initials_from_name("! !!"));
    }

}
