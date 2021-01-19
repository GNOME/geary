/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

private class Geary.App.RemoveOperation : BatchOperation<EmailIdentifier> {


    private Folder source_folder;


    public RemoveOperation(ConversationMonitor monitor,
                           Folder source_folder,
                           Gee.Collection<EmailIdentifier> removed_ids) {
        base(monitor, removed_ids);
        this.source_folder = source_folder;
    }

    public override async void execute_batch(Gee.Collection<EmailIdentifier> batch)
        throws GLib.Error {
        debug("Removing %d messages(s) from %s",
              batch.size, this.source_folder.to_string()
        );

        Gee.Set<Conversation> removed = new Gee.HashSet<Conversation>();
        Gee.MultiMap<Conversation,Email> trimmed =
            new Gee.HashMultiMap<Conversation, Geary.Email>();
        this.monitor.conversations.remove_all_emails_by_identifier(
            source_folder.path,
            batch,
            removed,
            trimmed
        );

        this.monitor.removed(
            removed,
            trimmed,
            (this.source_folder == this.monitor.base_folder) ? batch : null
        );

        // Queue an update since many emails may have been removed
        this.monitor.check_window_count();
    }

}
