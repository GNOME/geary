/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
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
        Geary.EmailIdentifier? lowest = this.monitor.window_lowest;
        Gee.Collection<EmailIdentifier>? to_insert = null;
        if (lowest != null) {
            to_insert = new Gee.LinkedList<EmailIdentifier>();
            foreach (EmailIdentifier inserted in batch) {
                if (lowest.natural_sort_comparator(inserted) < 0) {
                    to_insert.add(inserted);
                }
            }
        } else {
            to_insert = batch;
        }

        debug("Inserting %d of %d messages into %s",
              to_insert.size,
              batch.size,
              this.monitor.base_folder.to_string());
        yield this.monitor.load_by_sparse_id(to_insert);
    }
}
