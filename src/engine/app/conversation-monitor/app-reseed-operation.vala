/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * Re-scans the base folder for messages after its remote has opened.
 *
 * The reseed in effect checks for any existing message that did not
 * satisfy the email field requirements for the conversation monitor
 * or the required fields passed to its constructor, causing these
 * fields to be downloaded from the remote.
 */
private class Geary.App.ReseedOperation : ConversationOperation {


    public ReseedOperation(ConversationMonitor monitor) {
        base(monitor, false);
    }

    public override async void execute_async() throws Error {
        // Check for and load any newly appended messages
        EmailIdentifier? earliest_id = this.monitor.window_lowest;
        if (earliest_id != null) {
            debug("Reseeding starting from Email ID %s on opened %s",
                  earliest_id.to_string(), this.monitor.base_folder.to_string());
            // Some conversations have already been loaded, so check
            // from the earliest known right through to the end of the
            // vector for updated messages
            yield this.monitor.load_by_id_async(
                earliest_id,
                int.MAX,
                Folder.ListFlags.OLDEST_TO_NEWEST | Folder.ListFlags.INCLUDING_ID
            );
        }

        // Clear the fill flag since more messages may have appeared
        // after coming online, and do a check to get them filled if
        // needed.
        this.monitor.fill_complete = false;
        this.monitor.check_window_count();
    }

}
