/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

private class Geary.ImapEngine.OtherAccount : Geary.ImapEngine.GenericAccount {

    public OtherAccount(AccountInformation config,
                        ImapDB.Account local,
                        Endpoint incoming_remote,
                        Endpoint outgoing_remote) {
        base(config, local, incoming_remote, outgoing_remote);
    }

    protected override MinimalFolder new_folder(ImapDB.Folder local_folder) {
        FolderPath path = local_folder.get_path();
        SpecialFolderType type;
        if (Imap.MailboxSpecifier.folder_path_is_inbox(path)) {
            type = SpecialFolderType.INBOX;
        } else {
            type = local_folder.get_properties().attrs.get_special_folder_type();
            // There can be only one Inbox
            if (type == SpecialFolderType.INBOX) {
                type = SpecialFolderType.NONE;
            }
        }

        return new OtherFolder(this, local_folder, type);
    }

}
