/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

private class Geary.OutboxEmailProperties : Geary.EmailProperties {
    public OutboxEmailProperties() {
    }
    
    public override string to_string() {
        return "OutboxProperties";
    }
}

