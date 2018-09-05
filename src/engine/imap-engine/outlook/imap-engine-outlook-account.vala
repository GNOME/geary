/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.ImapEngine.OutlookAccount : Geary.ImapEngine.GenericAccount {


    public static void setup_service(ServiceInformation service) {
        switch (service.protocol) {
        case Protocol.IMAP:
            service.host = "imap-mail.outlook.com";
            service.port = Imap.ClientConnection.IMAP_TLS_PORT;
            service.use_ssl = true;
            break;

        case Protocol.SMTP:
            service.host = "smtp-mail.outlook.com";
            service.port = Smtp.ClientConnection.SUBMISSION_PORT;
            service.use_ssl = false;
            service.use_starttls = true;
            break;
        }
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
