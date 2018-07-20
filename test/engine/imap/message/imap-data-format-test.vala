/*
 * Copyright 2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

class Geary.Imap.DataFormatTest : Gee.TestCase {


    public DataFormatTest() {
        base("Geary.Imap.DataFormatTest");
        add_test("is_atom_special", is_atom_special);
    }

    public void is_atom_special() {
        assert_true(
            !DataFormat.is_atom_special('a') && !DataFormat.is_atom_special('z')
        );
        assert_true(
            !DataFormat.is_atom_special('A') && !DataFormat.is_atom_special('Z')
        );
        assert_true(
            !DataFormat.is_atom_special('0') && !DataFormat.is_atom_special('9')
        );
        assert_true(
            !DataFormat.is_atom_special('#') &&
            !DataFormat.is_atom_special('.') &&
            !DataFormat.is_atom_special('+') &&
            !DataFormat.is_atom_special('/') &&
            !DataFormat.is_atom_special('~') &&
            !DataFormat.is_atom_special(':')
        );

        // atom-specials
        assert_true(
            DataFormat.is_atom_special('(')
        );
        assert_true(
            DataFormat.is_atom_special(')')
        );
        assert_true(
            DataFormat.is_atom_special('{')
        );
        assert_true(
            DataFormat.is_atom_special(' ')
        );
        assert_true(
            DataFormat.is_atom_special(0x00)
        );
        assert_true(
            DataFormat.is_atom_special(0x1F)
        );
        assert_true(
            DataFormat.is_atom_special(0x7F)
        );
        assert_true(
            DataFormat.is_atom_special(0x80)
        );
        assert_true(
            DataFormat.is_atom_special(0xFE)
        );

        // list-wildcards
        assert_true(
            DataFormat.is_atom_special('%')
        );
        assert_true(
            DataFormat.is_atom_special('*')
        );

        // quoted-specials
        assert_true(
            DataFormat.is_atom_special('\"')
        );
        assert_true(
            DataFormat.is_atom_special('\\')
        );

        // resp-specials
        assert_true(
            DataFormat.is_atom_special(']')
        );
    }

}
