/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.App.MarkOperation : Geary.App.AsyncFolderOperation {
    public override Type folder_type { get { return typeof(Geary.FolderSupport.Mark); } }

    public Geary.EmailFlags? flags_to_add;
    public Geary.EmailFlags? flags_to_remove;

    public MarkOperation(Geary.EmailFlags? flags_to_add, Geary.EmailFlags? flags_to_remove) {
        this.flags_to_add = flags_to_add;
        this.flags_to_remove = flags_to_remove;
    }

    public override async Gee.Collection<Geary.EmailIdentifier> execute_async(
        Geary.Folder folder, Gee.Collection<Geary.EmailIdentifier> ids,
        Cancellable? cancellable) throws Error {
        Geary.FolderSupport.Mark? mark = folder as Geary.FolderSupport.Mark;
        assert(mark != null);

        yield mark.mark_email_async(
            Collection.copy(ids), flags_to_add, flags_to_remove, cancellable
        );
        return ids;
    }
}
