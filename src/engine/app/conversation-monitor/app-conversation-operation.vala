/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * An internal operation used to keep conversations up to date.
 *
 * Classes implementing this interface are used by {@link
 * ConversationMonitor} to asynchronously keep conversations up to
 * date as messages are added to, updated, and removed from folders.
 */
internal abstract class Geary.App.ConversationOperation : BaseObject {


    /** Determines if multiple instances of this operation can be queued. */
    public bool allow_duplicates { get; private set; }

    /** The monitor this operation will be applied to. */
    protected weak ConversationMonitor? monitor = null;


    protected ConversationOperation(ConversationMonitor? monitor,
                                    bool allow_duplicates = true) {
        this.monitor = monitor;
        this.allow_duplicates = allow_duplicates;
    }

    public abstract async void execute_async() throws Error;

}
