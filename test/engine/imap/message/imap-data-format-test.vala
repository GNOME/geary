/*
 * Copyright 2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

class Geary.Imap.DataFormatTest : TestCase {


    public DataFormatTest() {
        base("Geary.Imap.DataFormatTest");
        add_test("is_atom_special", is_atom_special);
    }

    public void is_atom_special() throws Error {
        assert_false(
            DataFormat.is_atom_special('a') || DataFormat.is_atom_special('z'),
            "Lower case ASCII"
        );
        assert_false(
            DataFormat.is_atom_special('A') || DataFormat.is_atom_special('Z'),
            "Upper case ASCII"
        );
        assert_false(
            DataFormat.is_atom_special('0') || DataFormat.is_atom_special('9'),
            "ASCII numbers"
        );
        assert_false(
            DataFormat.is_atom_special('#') ||
            DataFormat.is_atom_special('.') ||
            DataFormat.is_atom_special('+') ||
            DataFormat.is_atom_special('/') ||
            DataFormat.is_atom_special('~') ||
            DataFormat.is_atom_special(':'),
            "Common mailbox ASCII symbols"
        );

        // atom-specials
        assert_true(
            DataFormat.is_atom_special('('),
            "Atom-special: ("
        );
        assert_true(
            DataFormat.is_atom_special(')'),
            "Atom-special: )"
        );
        assert_true(
            DataFormat.is_atom_special('{'),
            "Atom-special: {"
        );
        assert_true(
            DataFormat.is_atom_special(' '),
            "Atom-special: SP"
        );
        assert_true(
            DataFormat.is_atom_special(0x00),
            "Atom-special: CTL (NUL)"
        );
        assert_true(
            DataFormat.is_atom_special(0x1F),
            "Atom-special: CTL (US)"
        );
        assert_true(
            DataFormat.is_atom_special(0x7F),
            "Atom-special: CTL (DEL)"
        );
        assert_true(
            DataFormat.is_atom_special(0x80),
            "Atom-special: Non-ASCII (0x80)"
        );
        assert_true(
            DataFormat.is_atom_special(0xFE),
            "Atom-special: Non-ASCII (0xFE)"
        );

        // list-wildcards
        assert_true(
            DataFormat.is_atom_special('%'),
            "Atom-special: %"
        );
        assert_true(
            DataFormat.is_atom_special('*'),
            "Atom-special: *"
        );

        // quoted-specials
        assert_true(
            DataFormat.is_atom_special('\"'),
            "Atom-special: \""
        );
        assert_true(
            DataFormat.is_atom_special('\\'),
            "Atom-special: \\"
        );

        // resp-specials
        assert_true(
            DataFormat.is_atom_special(']'),
            "Atom-special: ]"
        );
    }

}
