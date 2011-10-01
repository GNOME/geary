/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.ComposedEmail : Object {
    public DateTime date { get; set; }
    public string from { get; set; }
    public string? to { get; set; }
    public string? cc { get; set; }
    public string? bcc { get; set; }
    public string? subject { get; set; }
    public string? body { get; set; }
    
    public ComposedEmail(DateTime date, string from) {
        this.date = date;
        this.from = from;
    }
}

