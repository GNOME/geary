/* Copyright 2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

namespace Geary.Files {

// Number of files to delete in each step.
private const int RECURSIVE_DELETE_BATCH_SIZE = 50;

/**
 * Recursively deletes a folder and its children.
 * This method is designed to keep chugging along even if an error occurs.
 * If this method is called with a file, it will simply be deleted.
 */
public async void recursive_delete_async(File folder, Cancellable? cancellable = null) {
    // If this is a folder, recurse children.
    if (folder.query_file_type(FileQueryInfoFlags.NONE) == FileType.DIRECTORY) {
        FileEnumerator? enumerator = null;
        try {
            enumerator = yield folder.enumerate_children_async(FileAttribute.STANDARD_NAME,
                FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.DEFAULT, cancellable);
        } catch (Error e) {
            debug("Error enumerating files for deletion: %s", e.message);
        }
        
        // Iterate the enumerated files in batches.
        if (enumerator != null) {
            try {
                while (true) {
                    List<FileInfo>? info_list = yield enumerator.next_files_async(RECURSIVE_DELETE_BATCH_SIZE,
                        Priority.DEFAULT, cancellable);
                    if (info_list == null)
                        break; // Stop condition.
                    
                    // Recursive step.
                    foreach (FileInfo info in info_list)
                        yield recursive_delete_async(folder.get_child(info.get_name()), cancellable);
                }
            } catch (Error e) {
                debug("Error enumerating batch of files: %s", e.message);
            }
        }
    }
    
    // Children have been deleted, it's now safe to delete this file/folder.
    try {
        // TODO: Use File.delete_async() when GLib 2.34 is minimum requirement:
        // http://redmine.yorba.org/issues/6323
        folder.delete(cancellable);
    } catch (Error e) {
        debug("Error removing file: %s", e.message);
    }
}

public uint hash(File file) {
    return file.hash();
}

public bool equal(File a, File b) {
    return a.equal(b);
}

public uint nullable_hash(File? file) {
    return (file != null) ? file.hash() : 0;
}

public bool nullable_equal(File? a, File? b) {
    if (a == null && b == null)
        return true;
    
    if (a == null || b == null)
        return false;
    
    return a.equal(b);
}

}

