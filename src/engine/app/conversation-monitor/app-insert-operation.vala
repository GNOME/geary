/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Handles an insertion of messages from a monitor's base folder.
 */
private class Geary.App.InsertOperation : BatchOperation<EmailIdentifier> {


    public InsertOperation(ConversationMonitor monitor,
                           Gee.Collection<EmailIdentifier> inserted_ids) {
        base(monitor, inserted_ids);
    }

    public override async void execute_batch(Gee.Collection<EmailIdentifier> batch)
        throws GLib.Error {
        // Insert messages that are older than the current window
        // eldest only if the window is smaller than it could be, to
        // avoid involuntarily growing the window larger more than it
        // needs to be.
        bool needs_more = this.monitor.should_load_more;
        Geary.EmailIdentifier? lowest = this.monitor.window_lowest;
        if (lowest != null) {
            Gee.Iterator<EmailIdentifier> iter = batch.iterator();
            while (iter.next()) {
                EmailIdentifier inserted = iter.get();
                if (!needs_more && lowest.natural_sort_comparator(inserted) > 0) {
                    iter.remove();
                }
            }
        }

        if (!batch.is_empty) {
            debug("Inserting %u messages into %s",
                  batch.size,
                  this.monitor.base_folder.to_string());
            yield this.monitor.load_by_sparse_id(batch);
        } else {
            debug("Inserting no messages into %s, none needed",
                  this.monitor.base_folder.to_string());
        }
    }
}
