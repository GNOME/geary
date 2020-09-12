/*
 * Copyright © 2016 Software Freedom Conservancy Inc.
 * Copyright © 2018-2020 Michael Gratton <mike@vee.net>
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
public abstract class Geary.RemoteFolder : Folder {


    /**
     * Determines if the folder is checking for remote changes to email.
     *
     * @see start_monitoring
     * @see stop_monitoring
     */
    public abstract bool is_monitoring { get; }

    /**
     * Determines if the folder's local vector contains all remote email.
     *
     * This property is not guaranteed to be accurate at all times. It
     * is only updated whenever a connection to the remote folder is
     * established, i.e. by {@link start_monitoring}, {@link
     * synchronise}, {@link expand_vector} and others.
     */
    public abstract bool is_fully_expanded { get; }


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
     * This method requires the host is online, an error will be
     * thrown if the remote server cannot be reached.
     */
    public abstract async void expand_vector(GLib.Cancellable? cancellable)
        throws GLib.Error;

}
