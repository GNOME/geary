/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.EmailOrdering {
    public int64 ordinal { get; private set; }
    
    public EmailOrdering(int64 ordinal) {
        this.ordinal = ordinal;
    }
}

