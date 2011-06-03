/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Imap.EmailHeader : Geary.EmailHeader {
    public EmailHeader(int msg_num, Envelope envelope) {
        base (msg_num, envelope.from, envelope.subject, envelope.sent);
    }
}

public class Geary.Imap.EmailBody : Geary.EmailBody {
    public EmailBody(EmailHeader header, string full) {
        base (header, full);
    }
}

