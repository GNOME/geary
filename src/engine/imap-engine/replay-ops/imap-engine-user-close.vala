/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.ImapEngine.UserClose : Geary.ImapEngine.ReplayOperation {

    /** A function that this operation can call to close the folder. */
    public delegate bool CloseFolder();

    /** Determines the state of the close operation. */
    public Trillian is_closing = Trillian.UNKNOWN;

    private CloseFolder close;


    public UserClose(owned CloseFolder close) {
        base ("UserClose", Scope.LOCAL_ONLY);
        this.close = (owned) close;
    }

    public override void notify_remote_removed_position(Imap.SequenceNumber removed) {
    }

    public override void notify_remote_removed_ids(Gee.Collection<ImapDB.EmailIdentifier> ids) {
    }

    public override void get_ids_to_be_remote_removed(Gee.Collection<ImapDB.EmailIdentifier> ids) {
    }

    public override async ReplayOperation.Status replay_local_async() throws Error {
        bool closing = this.close();
        this.is_closing = Trillian.from_boolean(closing);
        return ReplayOperation.Status.COMPLETED;
    }

    public override async void backout_local_async() throws Error {
    }

    public override async ReplayOperation.Status replay_remote_async() throws Error {
        // should not be called
        return ReplayOperation.Status.COMPLETED;
    }

    public override string describe_state() {
        return "is_closing: %s".printf(this.is_closing.to_string());
    }

}
