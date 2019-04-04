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

        Gee.Set<Conversation> removed = new Gee.HashSet<Conversation>();
        Gee.MultiMap<Conversation,Email> trimmed =
            new Gee.HashMultiMap<Conversation, Geary.Email>();
        this.monitor.conversations.remove_all_emails_by_identifier(
            source_folder.path,
            removed_ids,
            removed,
            trimmed
        );


        // Fire signals, clean up
        this.monitor.removed(
            removed,
            trimmed,
            (this.source_folder == this.monitor.base_folder) ? this.removed_ids : null
        );
    }

}
