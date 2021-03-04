/*
 * Copyright © 2016 Software Freedom Conservancy Inc.
 * Copyright © 2018-2021 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * A folder that is backed by a remote email service.
 *
 * While {@link Folder} provides a means to access and manipulate
 * locally stored email, this class provides a means to update and
 * synchronise with a folder that exists on a remote email service.
 *
 * The set of locally stored messages is called the folder's
 * ''vector'', and contains generally the most recent message in the
 * mailbox at the upper end, back through to some older message at the
 * start or lower end of the vector. The vector may not contain all
 * email present in the remote folder, but it should generally always
 * contain the most recent. The ordering of the vector is the
 * ''natural'' ordering, based on the order in which messages were
 * appended to the folder, not when messages were sent or some other
 * criteria.
 *
 * Several operations cause the vector to be updated. Both {@link
 * start_monitoring} and {@link synchronise} will ensure that the
 * vector's upper end is up-to-date with the remote, so that it
 * contains the most recent email found in the remote folder. The
 * engine will automatically maintain the lower end of the vector in
 * accordance with the value of {@link
 * AccountInformation.prefetch_period_days}, however the start of the
 * vector can be extended back past that over time via {@link
 * expand_vector}, causing the lower end of the vector to be
 * temporarily ''expanded''.
 */
public interface Geary.RemoteFolder : Folder {


    /** A collection of known properties about a remote mailbox. */
    public interface RemoteProperties : GLib.Object {


        /**
         * The total count of email in the remote mailbox.
         */
        public abstract int email_total { get; protected set; }

        /**
         * The total count of unread email in the remote mailbox.
         */
        public abstract int email_unread { get; protected set; }

        /**
         * Indicates whether the remote mailbox has children.
         *
         * Note that if {@link has_children} == {@link
         * Trillian.TRUE}, it implies {@link supports_children} ==
         * {@link Trillian.TRUE}.
         */
        public abstract Trillian has_children { get; protected set; }

        /**
         * Indicates whether the remote mailbox can have children.
         *
         * This does ''not'' mean creating a sub-folder is guaranteed
         * to succeed.
         */
        public abstract Trillian supports_children { get; protected set; }

        /**
         * Indicates whether the remote mailbox can be opened.
         *
         * Mailboxes that cannot be opened exist as steps in the
         * mailbox name-space only - they do not contain email.
         */
        public abstract Trillian is_openable { get; protected set; }

        /**
         * Indicates whether the remote mailbox reports ids for created email.
         *
         * True if a folder supporting {@link FolderSupport.Create}
         * will not to return a {@link EmailIdentifier} when a call to
         * {@link FolderSupport.Create.create_email_async} succeeds.
         *
         * This is for IMAP servers that don't support UIDPLUS. Most
         * servers support UIDPLUS, so this will usually be false.
         */
        public abstract bool create_never_returns_id { get; protected set; }

    }


    /**
     * Last known properties of this folder's remote mailbox.
     *
     * This property is not guaranteed to be accurate at all times. It
     * is only updated whenever a connection to the remote folder is
     * established, i.e. by {@link start_monitoring}, {@link
     * synchronise}, {@link expand_vector} and others, and in response
     * to notifications from the server.
     *
     * Note that remote properties may change even when there is no
     * current connection to this remote folder (that is, if {@link
     * is_connected} is false), since another connection may have
     * provided updated information.
     */
    public abstract RemoteProperties remote_properties { get; }

    /**
     * Indicates if the folder's local vector contains all remote email.
     *
     * This property is not guaranteed to be accurate at all times. It
     * is only updated at the same times as {@link remote_properties}.
     */
    public abstract bool is_fully_expanded { get; }

    /**
     * Indicates if the folder is checking for remote changes to email.
     *
     * @see start_monitoring
     * @see stop_monitoring
     */
    public abstract bool is_monitoring { get; }


    /**
     * Starts the folder checking for remote changes to email.
     *
     * Depending on the implementation, this may require opening a
     * connection to the server, having the remote folder selected,
     * and so on.
     *
     * This method does not wait for any remote connection to be made,
     * it simply flags that monitoring should occur. If the host is
     * online, a connection to the remote folder will be established
     * in the background and an implicit call to {@link synchronise}
     * will be made. If the host is offline or if it goes offline
     * sometime later, the folder will wait until being back online
     * before re-connecting and re-sync'ing.
     *
     * @see stop_monitoring
     */
    public abstract void start_monitoring();

    /**
     * Stops the folder checking for remote changes to email.
     *
     * @see start_monitoring
     */
    public abstract void stop_monitoring();

    /**
     * Synchronises the folder's contents with the remote.
     *
     * Depending on the implementation, this may require opening a
     * connection to the server, having the remote folder open, and so
     * on.
     *
     * This method requires the host is online, an error will be
     * thrown if the remote server cannot be reached.
     */
    public abstract async void synchronise(GLib.Cancellable? cancellable)
        throws GLib.Error;

    /**
     * Extends the lower, start of the folder back past the usual
     * limit.
     *
     * Depending on the implementation, this may require opening a
     * connection to the server, having the remote folder open, and so
     * on.
     *
     * The vector will be attempted to be extended back to both the
     * date (if given) and by the number of email messages (if
     * given). If neither are specified no attempt will be made to
     * expand the vector.
     *
     * This method requires the host is online, an error will be
     * thrown if the remote server cannot be reached.
     */
    public abstract async void expand_vector(GLib.DateTime? target_date,
                                             uint? target_count,
                                             GLib.Cancellable? cancellable)
        throws GLib.Error;

}
