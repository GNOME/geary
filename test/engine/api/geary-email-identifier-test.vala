/*
 * Copyright 2017 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

public class Geary.MockEmailIdentifer : EmailIdentifier {


    private int id;


    public MockEmailIdentifer(int id) {
        base(id.to_string());
        this.id = id;
    }

    public override int natural_sort_comparator(Geary.EmailIdentifier other) {
        MockEmailIdentifer? other_mock = other as MockEmailIdentifer;
        return (other_mock == null) ? -1 : other_mock.id - this.id;
    }

}
