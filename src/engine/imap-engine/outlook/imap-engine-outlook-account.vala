/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.ImapEngine.OutlookAccount : Geary.ImapEngine.GenericAccount {

    public static Geary.Endpoint generate_imap_endpoint() {
        Geary.Endpoint endpoint = new Geary.Endpoint(
            "imap-mail.outlook.com",
            Imap.ClientConnection.DEFAULT_PORT_SSL,
            Geary.Endpoint.Flags.SSL,
            Imap.ClientConnection.RECOMMENDED_TIMEOUT_SEC);
        // As of June 2016, outlook.com's IMAP servers have a bug
        // where a large number (~50) of pipelined STATUS commands on
        // mailboxes with many messages will eventually cause it to
        // break command parsing and return a BAD response, causing us
        // to drop the connection. Limit the number of pipelined
        // commands per batch to work around this.  See b.g.o Bug
        // 766552
        endpoint.max_pipeline_batch_size = 25;
        return endpoint;
    }

    public static Geary.Endpoint generate_smtp_endpoint() {
        return new Geary.Endpoint(
            "smtp-mail.outlook.com",
            Smtp.ClientConnection.DEFAULT_PORT_STARTTLS,
            Geary.Endpoint.Flags.STARTTLS,
            Smtp.ClientConnection.DEFAULT_TIMEOUT_SEC);
    }

    public OutlookAccount(string name,
                          AccountInformation account_information,
                          ImapDB.Account local) {
        base(name, account_information, local);
    }

    protected override MinimalFolder new_folder(ImapDB.Folder local_folder) {
        // use the Folder's attributes to determine if it's a special folder type, unless it's
        // INBOX; that's determined by name
        Geary.FolderPath path = local_folder.get_path();
        SpecialFolderType special_folder_type;
        if (Imap.MailboxSpecifier.folder_path_is_inbox(path))
            special_folder_type = SpecialFolderType.INBOX;
        else
            special_folder_type = local_folder.get_properties().attrs.get_special_folder_type();

        if (special_folder_type == Geary.SpecialFolderType.DRAFTS)
            return new OutlookDraftsFolder(this, local_folder, special_folder_type);

        return new OutlookFolder(this, local_folder, special_folder_type);
    }

}
