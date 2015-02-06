/* Copyright 2013-2015 Yorba Foundation
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
    FileType file_type = FileType.UNKNOWN;
    try {
        file_type = yield query_file_type_async(folder, true, cancellable);
    } catch (Error err) {
        debug("Unable to get file type of %s: %s", folder.get_path(), err.message);
        
        if (err is IOError.CANCELLED)
            return;
    }
    
    if (file_type == FileType.DIRECTORY) {
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
                
                if (e is IOError.CANCELLED)
                    return;
            }
        }
    }
    
    // Children have been deleted, it's now safe to delete this file/folder.
    try {
        yield folder.delete_async(Priority.DEFAULT, cancellable);
    } catch (Error e) {
        debug("Error removing file: %s", e.message);
    }
}

/**
 * Asynchronously report if the File exists.
 */
public async bool query_exists_async(File file, Cancellable? cancellable = null) throws Error {
    try {
        yield query_file_type_async(file, true, cancellable);
    } catch (Error err) {
        if (err is IOError.NOT_FOUND)
            return false;
        else
            throw err;
    }
    
    // exists if got this far
    return true;
}

/**
 * Asynchronously fetch the FileType of the File.
 */
public async FileType query_file_type_async(File file, bool follow_symlinks, Cancellable? cancellable = null)
    throws Error {
    FileInfo info = yield file.query_info_async("standard::type",
        follow_symlinks ? FileQueryInfoFlags.NONE : FileQueryInfoFlags.NOFOLLOW_SYMLINKS,
        Priority.DEFAULT, cancellable);
    
    return info.get_file_type();
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

