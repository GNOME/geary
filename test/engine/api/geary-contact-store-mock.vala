/*
 * Copyright 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

internal class Geary.ContactStoreMock : ContactStore, MockObject, GLib.Object {

    protected Gee.Queue<ExpectedCall> expected {
        get; set; default = new Gee.LinkedList<ExpectedCall>();
    }

    public async Contact? get_by_rfc822(Geary.RFC822.MailboxAddress address,
                                        GLib.Cancellable? cancellable)
        throws GLib.Error {
        return object_call<Contact?>("get_by_rfc822", { address }, null);
    }

    public async void update_contacts(Gee.Collection<Contact> updated,
                                      GLib.Cancellable? cancellable)
        throws GLib.Error {
        void_call("update_contacts", { updated, cancellable });
    }

}
