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


    public override void load_settings(Geary.ConfigFile.Group config)
        throws Error {
        void_call("load_settings", { box_arg(config) });
    }

    public override void load_credentials(Geary.ConfigFile.Group config,
                                          string? email_address = null)
        throws Error {
        void_call("load_credentials", { box_arg(config), box_arg(email_address) });
    }

    public override void save_settings(Geary.ConfigFile.Group config) {
        try {
            void_call("save_settings", { box_arg(config) });
        } catch (Error err) {
            assert_not_reached();
        }
    }

}
