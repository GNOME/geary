/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.EmailLocation : Object {
    public int position { get; private set; }
    
    public EmailLocation(int position) {
        this.position = position;
    }
}

