/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.App.ListOperation : Geary.App.AsyncFolderOperation {
    public override Type folder_type { get { return typeof(Geary.Folder); } }

    public Gee.HashSet<Geary.Email> results;
    public Geary.Email.Field required_fields;
    public Geary.Folder.ListFlags flags;

    public ListOperation(Geary.Email.Field required_fields, Geary.Folder.ListFlags flags) {
        results = new Gee.HashSet<Geary.Email>();
        this.required_fields = required_fields;
        this.flags = flags;
    }

    public override async Gee.Collection<Geary.EmailIdentifier> execute_async(
        Geary.Folder folder, Gee.Collection<Geary.EmailIdentifier> ids,
        Cancellable? cancellable) throws Error {
        Gee.List<Geary.Email>? list = yield folder.list_email_by_sparse_id_async(
            ids, required_fields, flags, cancellable);
        if (list != null)
            results.add_all(list);
        return ids;
    }
}
