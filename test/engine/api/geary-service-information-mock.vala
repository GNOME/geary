/*
 * Copyright 2017 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

public class Geary.MockServiceInformation : ServiceInformation, MockObject {


    protected Gee.Queue<ExpectedCall> expected {
        get; set; default = new Gee.LinkedList<ExpectedCall>();
    }

    public MockServiceInformation() {
        base(Service.IMAP);
    }

    public override Geary.ServiceInformation temp_copy() {
        try {
            return object_call<Geary.ServiceInformation>(
                "temp_copy", { }, new MockServiceInformation()
            );
        } catch (GLib.Error err) {
            assert_not_reached();
        }
    }

}
