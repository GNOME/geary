/* Copyright 2016 Software Freedom Conservancy Inc.
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
public async void recursive_delete_async(GLib.File folder,
                                         int priority = GLib.Priority.DEFAULT,
                                         GLib.Cancellable? cancellable = null)
    throws GLib.Error {
    GLib.FileType type = yield query_file_type_async(folder, true, cancellable);

    // If this is a folder, recurse children.
    if (type == DIRECTORY) {
        FileEnumerator? enumerator = yield folder.enumerate_children_async(
                FileAttribute.STANDARD_NAME,
                NOFOLLOW_SYMLINKS,
                priority,
                cancellable
        );

        // Iterate the enumerated files in batches.
        if (enumerator != null) {
            while (true) {
                List<FileInfo>? info_list = yield enumerator.next_files_async(
                    RECURSIVE_DELETE_BATCH_SIZE,
                    priority,
                    cancellable
                );
                if (info_list == null) {
                    break; // Stop condition.
                }

                // Recursive step.
                foreach (FileInfo info in info_list) {
                    yield recursive_delete_async(
                        folder.get_child(info.get_name()),
                        priority,
                        cancellable
                    );
                }
            }
        }
    }

    // Children have been deleted, it's now safe to delete this file/folder.
    yield folder.delete_async(priority, cancellable);
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

/**
 * Ensure a directory exists, asynchronously.
 *
 * Returns true if the directory ws created. A {@link GLib.Error} is
 * thrown if the directory cannot be created, but not if it already
 * exists.
 */
public async bool make_directory_with_parents(File dir,
                                              Cancellable? cancellable = null)
    throws Error {
    bool ret = false;
    GLib.IOError? create_err = null;
    yield Nonblocking.Concurrent.global.schedule_async(() => {
            try {
                dir.make_directory_with_parents(cancellable);
            } catch (GLib.IOError err) {
                create_err = err;
            }
        });

    if (create_err == null) {
        ret = true;
    } else if (!(create_err is GLib.IOError.EXISTS)) {
        throw create_err;
    }

    return ret;
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

