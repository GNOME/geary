/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

private class Geary.App.AppendOperation : BatchOperation<EmailIdentifier> {


    public AppendOperation(ConversationMonitor monitor,
                           Gee.Collection<EmailIdentifier> appended_ids) {
        base(monitor, appended_ids);
    }

    public override async void execute_batch(Gee.Collection<EmailIdentifier> batch)
        throws GLib.Error {
        debug("Appending %d message(s) to %s",
              batch.size, this.monitor.base_folder.to_string());

        yield this.monitor.load_by_sparse_id(batch);
    }

}
