/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

private class Geary.Imap.EmailLocation : Geary.EmailLocation {
    public int64 uid { get; private set; }
    
    public EmailLocation(int position, int64 uid) {
        base (position);
        
        this.uid = uid;
    }
}

