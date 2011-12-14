/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public abstract class Geary.EmailProperties : Object {
    
    // Flags set on the email object.
    public EmailFlags email_flags { get; set; }
        
    public EmailProperties() {
    }
}

