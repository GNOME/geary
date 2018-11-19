/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Operation to close the folder.
 *
 * This is a replay queue operation to allow existing local ops to
 * complete, and to ease the implementation. See comments in {@link
 * MinimalFolder.close_async}.
 */
private class Geary.ImapEngine.UserClose : Geary.ImapEngine.ReplayOperation {

    /** Determines the state of the close operation. */
    public Trillian is_closing = Trillian.UNKNOWN;

    private MinimalFolder owner;
    private Cancellable? cancellable;


    public UserClose(MinimalFolder owner, Cancellable? cancellable) {
        base("UserClose", Scope.LOCAL_ONLY);
        this.owner = owner;
        this.cancellable = cancellable;
    }

    public override async ReplayOperation.Status replay_local_async() throws Error {
        bool closing = yield this.owner.close_internal(
            Folder.CloseReason.LOCAL_CLOSE,
            Folder.CloseReason.REMOTE_CLOSE,
            this.cancellable
        );
        this.is_closing = Trillian.from_boolean(closing);
        return ReplayOperation.Status.COMPLETED;
    }

    public override string describe_state() {
        return "is_closing: %s".printf(this.is_closing.to_string());
    }

}
