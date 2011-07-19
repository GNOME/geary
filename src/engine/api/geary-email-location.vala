/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.EmailLocation : Object {
    public int position { get; private set; }
    public int64 ordering { get; private set; }
    
    public EmailLocation(int position, int64 ordering) {
        this.position = position;
        this.ordering = ordering;
    }
}

