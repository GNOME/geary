/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
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
        EmailIdentifier? earliest_id =
            yield this.monitor.get_lowest_email_id_async();
        if (earliest_id != null) {
            debug("Reseeding starting from Email ID %s on opened %s",
                  earliest_id.to_string(), this.monitor.base_folder.to_string());
            // Some conversations have already been loaded, so check
            // from the earliest known right through to the end of the
            // vector for updated mesages
            yield this.monitor.load_by_id_async(
                earliest_id,
                int.MAX,
                Folder.ListFlags.OLDEST_TO_NEWEST | Folder.ListFlags.INCLUDING_ID
            );
        } else {
            // No conversations are present, so do a check to get the
            // side effect of queuing a fill operation.
            this.monitor.check_window_count();
        }
    }

}
