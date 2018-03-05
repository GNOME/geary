/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.App.RemoveOperation : ConversationOperation {

    private Geary.Folder source_folder;
    private Gee.Collection<Geary.EmailIdentifier> removed_ids;

    public RemoveOperation(ConversationMonitor monitor,
                           Geary.Folder source_folder,
                           Gee.Collection<Geary.EmailIdentifier> removed_ids) {
        base(monitor);
        this.source_folder = source_folder;
        this.removed_ids = removed_ids;
    }

    public override async void execute_async() throws Error {
        debug("%d messages(s) removed from %s, trimming/removing conversations...",
              this.removed_ids.size, this.source_folder.to_string()
        );

        Gee.Collection<Conversation> removed;
        Gee.MultiMap<Conversation,Email> trimmed;
        this.monitor.conversations.remove_all_emails_by_identifier(
            source_folder.path,
            removed_ids,
            out removed,
            out trimmed
        );

        // Check for conversations that have been evaporated as a
        // result, update removed and trimmed collections to reflect
        // any that evaporated
        Gee.Collection<Conversation> evaporated =
            yield this.monitor.check_conversations_in_base_folder(trimmed.get_keys());
        removed.add_all(evaporated);
        foreach (Conversation target in evaporated) {
            trimmed.remove_all(target);
        }

        // Fire signals, clean up
        this.monitor.notify_emails_removed(removed, trimmed);

        // Check we still have enough conversations if any were
        // removed
        if (!removed.is_empty) {
            this.monitor.check_window_count();
        }
    }

}
