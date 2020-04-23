/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

// A FolderEntry for inboxes in the Inboxes branch.
public class FolderList.InboxFolderEntry : FolderList.FolderEntry {


    private string display_name = "";


    public InboxFolderEntry(Application.FolderContext context) {
        base(context);
        this.display_name = context.folder.account.information.display_name;
        context.folder.account.information.changed.connect(on_information_changed);
    }

    ~InboxFolderEntry() {
        folder.account.information.changed.disconnect(on_information_changed);
    }

    public override string get_sidebar_name() {
        return this.display_name;
    }

    public Geary.AccountInformation get_account_information() {
        return folder.account.information;
    }

    private void on_information_changed(Geary.AccountInformation config) {
        if (this.display_name != config.display_name) {
            this.display_name = config.display_name;
            entry_changed();
        }
    }
}
