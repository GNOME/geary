/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public int compare_email(Geary.Email aenvelope, Geary.Email benvelope) {
    int diff = aenvelope.date.value.compare(benvelope.date.value);
    if (diff != 0)
        return diff;
    
    // stabilize sort by using the mail's position, which is always unique in a folder
    return aenvelope.location.position - benvelope.location.position;
}
