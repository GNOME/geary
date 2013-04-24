/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public interface Geary.Imap.Serializable {
    public abstract async void serialize(Serializer ser) throws Error;
}

