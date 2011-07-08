/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

private class Geary.GenericImapFolder : Geary.EngineFolder {
    public GenericImapFolder(RemoteAccount remote, LocalAccount local, LocalFolder local_folder) {
        base (remote, local, local_folder);
    }
}
