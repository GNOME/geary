/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

/*
 * The IMAP implementation of Geary.EmailLocation uses the email's UID to order the messages.
 */

private class Geary.Imap.EmailLocation : Geary.EmailLocation {
    public EmailLocation(int position, Geary.Imap.UID uid) {
        base (position, uid.value);
    }
}

