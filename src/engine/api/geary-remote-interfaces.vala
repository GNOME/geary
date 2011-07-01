/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public interface Geary.RemoteAccount : Object, Geary.Account {
    public abstract async string? get_folder_delimiter_async(string toplevel,
        Cancellable? cancellable = null) throws Error;
}

public interface Geary.RemoteFolder : Object, Geary.Folder {
}

