/*
 * Copyright 2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

class Geary.Imap.ListParameterTest : TestCase {


    public ListParameterTest() {
        base("Geary.Imap.ListParameterTest");
        add_test("add_to_multiple_parents", add_to_multiple_parents);
    }

    // See GitLab Issue #26
    public void add_to_multiple_parents() throws GLib.Error {
        ListParameter child = new ListParameter();

        ListParameter parent_1 = new ListParameter();
        ListParameter parent_2 = new ListParameter();

        parent_1.add(child);
        parent_2.add(child);

        assert_equal<int?>(parent_1.size, 1, "Parent 1 does not contain child");
        assert_equal<int?>(parent_2.size, 1, "Parent 2 does not contain child");
    }

}
