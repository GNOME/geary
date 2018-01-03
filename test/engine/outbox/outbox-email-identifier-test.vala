/*
 * Copyright 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

public class Geary.Outbox.EmailIdentifierTest : TestCase {


    public EmailIdentifierTest() {
        base("Geary.Outbox.EmailIdentifierTest");
        add_test("variant_representation", variant_representation);
    }

    public void variant_representation() throws GLib.Error {
        EmailIdentifier orig = new EmailIdentifier(123, 321);
        GLib.Variant variant = orig.to_variant();
        EmailIdentifier copy = new EmailIdentifier.from_variant(variant);

        assert_true(orig.equal_to(copy));
    }

}
