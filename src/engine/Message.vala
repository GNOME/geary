/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Message {
    public int msg_num { get; private set; }
    public string from { get; private set; }
    public string subject { get; private set; }
    public string sent { get; private set; }
    
    public Message(int msg_num, string from, string subject, string sent) {
        this.msg_num = msg_num;
        this.from = from;
        this.subject = subject;
        this.sent = sent;
    }
    
    public string to_string() {
        return "[%d] %s: %s (%s)".printf(msg_num, from, subject, sent);
    }
}

