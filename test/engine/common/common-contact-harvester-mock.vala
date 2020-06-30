/*
 * Copyright 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

internal class Geary.MockContactHarvester :
    Geary.BaseObject,
    ContactHarvester {

    public async void harvest_from_email(Gee.Collection<Email> messages,
                                         GLib.Cancellable? cancellable)
        throws GLib.Error {
    }

}
