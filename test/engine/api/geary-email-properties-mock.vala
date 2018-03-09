/*
 * Copyright 2017 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

public class Geary.MockEmailProperties : EmailProperties {


    public MockEmailProperties(GLib.DateTime received) {
        base(received, 0);
    }

    public override string to_string() {
        return "MockEmailProperties: %s/%lli".printf(
            this.date_received.to_string(), this.total_bytes
        );
    }

}
