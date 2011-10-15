/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

private interface Geary.Imap.FolderExtensions : Geary.Folder {
    /**
     * Much like Geary.Folder.list_email_async(), but this list operation allows for a range of
     * emails to be specified by their UID rather than position (message number).  If low is null
     * that indicates to search from the lowest UID (1) to high.  Likewise, if high is null it
     * indicates to search from low to the highest UID.  Setting both to null will return all
     * emails in the folder.
     *
     * Unlike list_email_async(), this call guarantees that the messages will be returned in UID
     * order, from lowest to highest.
     *
     * The folder must be open before making this call.
     */
    public abstract async Gee.List<Geary.Email>? list_email_uid_async(Geary.Imap.UID? low,
        Geary.Imap.UID? high, Geary.Email.Field fields, Cancellable? cancellable = null)
        throws Error;
}

