/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

/**
 * Each mail system muse have its own method for uniquely identifying an email message.  The only
 * limitation upon an EmailIdentifier is that it's only considered valid within the Folder the
 * message is located in; an EmailIdentifier cannot be used in another Folder to determine if the
 * message is duplicated there.  (Either EmailIdentifier will be expanded to allow for this or
 * another system will be offered.)
 */

public abstract class Geary.EmailIdentifier : Object, Geary.Equalable {
    public abstract bool equals(Geary.Equalable other);
    
    public abstract string to_string();
}

