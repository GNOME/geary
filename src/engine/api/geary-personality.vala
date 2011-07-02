/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public interface Geary.Personality : Object {
    public abstract string get_user_folders_label();
    
    public abstract Geary.SpecialFolderMap? get_special_folder_map();
    
    public abstract Gee.Set<Geary.FolderPath>? get_ignored_paths();
}

