/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Handles an insertion of messages from a monitor's base folder.
 */
private class Geary.App.InsertOperation : ConversationOperation {


    private Gee.Collection<EmailIdentifier> inserted_ids;

    public InsertOperation(ConversationMonitor monitor,
                           Gee.Collection<EmailIdentifier> inserted_ids) {
        base(monitor);
        this.inserted_ids = inserted_ids;
    }

    public override async void execute_async() throws Error {
        Geary.EmailIdentifier? lowest = this.monitor.window_lowest;
        Gee.Collection<EmailIdentifier>? to_insert = null;
        if (lowest != null) {
            to_insert = new Gee.LinkedList<EmailIdentifier>();
            foreach (EmailIdentifier inserted in this.inserted_ids) {
                if (lowest.natural_sort_comparator(inserted) < 0) {
                    to_insert.add(inserted);
                }
            }
        } else {
            to_insert = this.inserted_ids;
        }

        debug("Inserting %d messages in %s after %d inserted...",
              to_insert.size,
              this.monitor.base_folder.to_string(),
              this.inserted_ids.size);
        yield this.monitor.load_by_sparse_id(to_insert);
    }
}
