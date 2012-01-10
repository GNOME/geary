/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

private interface Geary.RemoteAccount : Object, Geary.Account {
    /**
     * Delivers a formatted message with this Account being the sender of record.
     *
     * TODO: The Account object should enqueue messages and notify of their transmission.  Currently
     * this method initiates delivery.
     */
    public abstract async void send_email_async(Geary.ComposedEmail composed, Cancellable? cancellable = null)
        throws Error;
}

private interface Geary.RemoteFolder : Object, Geary.Folder {
    /**
     * A remote folder may report *either* a message has been removed by its EmailIdentifier
     * (in which case it should use "message-removed") or by its position (in which case it should
     * use this signal, "message-at-removed"), but never both for the same removal.
     */
    public signal void message_at_removed(int position, int total);
    
    protected abstract void notify_message_at_removed(int position, int total);
}

