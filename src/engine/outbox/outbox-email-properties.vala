/*
 *  Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

private class Geary.Outbox.EmailProperties : Geary.EmailProperties {


    public EmailProperties(GLib.DateTime date_received, long total_bytes) {
        base(date_received, total_bytes);
    }

    public override string to_string() {
        return "Outbox.Properties";
    }

}
