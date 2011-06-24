/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

//
// The EmailLocation for any message originating from an ImapAccount is guaranteed to have its
// UID attached to it, whether or not it was requested in the FETCH operation.
//

private class Geary.Imap.EmailLocation : Geary.EmailLocation {
    public Geary.Imap.UID uid { get; private set; }
    
    public EmailLocation(int position, Geary.Imap.UID uid) {
        base (position);
        
        this.uid = uid;
    }
}

