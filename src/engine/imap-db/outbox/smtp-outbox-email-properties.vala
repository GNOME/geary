/* Copyright 2011-2015 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.SmtpOutboxEmailProperties : Geary.EmailProperties {
    public SmtpOutboxEmailProperties(DateTime date_received, long total_bytes) {
        base(date_received, total_bytes);
    }
    
    public override string to_string() {
        return "SmtpOutboxProperties";
    }
}

