/*
 * Copyright © 2017-2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

public class Mock.ClientService : Geary.ClientService {


    public ClientService(Geary.AccountInformation account,
                         Geary.ServiceInformation configuration,
                         Geary.Endpoint remote) {
        base(account, configuration, remote);
    }

    public override async void start(GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        throw new Geary.EngineError.UNSUPPORTED("Mock method");
    }

    public override async void stop(GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        throw new Geary.EngineError.UNSUPPORTED("Mock method");
    }

    public override void became_reachable() {

    }

    public override void became_unreachable() {

    }

}
