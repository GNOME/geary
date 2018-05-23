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


    public override void load_settings(KeyFile? key_file = null)
        throws Error {
        void_call("load_settings", { box_arg(key_file) });
    }

    public override void load_credentials(KeyFile? key_file = null,
                                          string? email_address = null)
        throws Error {
        void_call("load_credentials", { box_arg(key_file), box_arg(email_address) });
    }

    public override void save_settings(KeyFile? key_file = null) {
        try {
            void_call("save_settings", { box_arg(key_file) });
        } catch (Error err) {
            assert_not_reached();
        }
    }

}
