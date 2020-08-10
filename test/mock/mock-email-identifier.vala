/*
 * Copyright 2017 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

public class Mock.EmailIdentifer : Geary.EmailIdentifier {


    private int id;


    public EmailIdentifer(int id) {
        this.id = id;
    }

    public override uint hash() {
        return GLib.int_hash(this.id);
    }

    public override bool equal_to(Geary.EmailIdentifier other) {
        return (
            this.get_type() == other.get_type() &&
            this.id == ((EmailIdentifer) other).id
        );
    }


    public override string to_string() {
        return "%s(%d)".printf(
            this.get_type().name(),
            this.id
        );
    }

    public override GLib.Variant to_variant() {
        return new GLib.Variant.int32(id);
    }

    public override int natural_sort_comparator(Geary.EmailIdentifier other) {
        EmailIdentifer? other_mock = other as EmailIdentifer;
        return (other_mock == null) ? 1 : this.id - other_mock.id;
    }

}
