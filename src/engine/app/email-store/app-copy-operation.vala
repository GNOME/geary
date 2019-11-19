/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.App.CopyOperation : Geary.App.AsyncFolderOperation {
    public override Type folder_type { get { return typeof(Geary.FolderSupport.Copy); } }

    public Geary.FolderPath destination;

    public CopyOperation(Geary.FolderPath destination) {
        this.destination = destination;
    }

    public override async Gee.Collection<Geary.EmailIdentifier> execute_async(
        Geary.Folder folder, Gee.Collection<Geary.EmailIdentifier> ids,
        Cancellable? cancellable) throws Error {
        Geary.FolderSupport.Copy? copy = folder as Geary.FolderSupport.Copy;
        assert(copy != null);

        yield copy.copy_email_async(
            Collection.copy(ids), destination, cancellable
        );
        return ids;
    }
}
