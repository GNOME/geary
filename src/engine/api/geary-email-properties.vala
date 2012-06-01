/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

/**
 * EmailProperties holds (in general) immutable metadata about an Email.  EmailFlags used to be
 * held here and retrieved via Email.Field.PROPERTIES, but as they're mutable, they were broken out
 * for efficiency reasons.
 *
 * Currently EmailProperties offers nothing to clients of the Geary engine.  In the future it may
 * be expanded to supply details like when the message was added to the local store, checksums,
 * and so forth.
 */

public abstract class Geary.EmailProperties : Object {
    public EmailProperties() {
    }
    
    public abstract string to_string();
}

