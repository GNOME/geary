/*
 * Copyright © 2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */


/**
 * Collects application state related to a single folder.
 */
public class Application.FolderContext : Geary.BaseObject,
    Gee.Comparable<FolderContext> {


    /** Specifies different kinds of displayable email counts. */
    public enum EmailCount {
        /** No email count should be displayed. */
        NONE,
        /** The unread email count should be displayed. */
        UNREAD,
        /** The total email count should be displayed. */
        TOTAL;
    }

    /** The account for this context. */
    public Geary.Folder folder { get; private set; }

    /** Returns the human-readable name of the folder */
    public string display_name { get; set; }

    /** The icon to use for the folder */
    public string icon_name { get; set; }

    /** The count to be displayed for the folder. */
    public EmailCount displayed_count { get; set; }


    public FolderContext(Geary.Folder folder) {
        this.folder = folder;
        this.folder.use_changed.connect(() => update());
        update();
    }

    public int compare_to(FolderContext other) {
        return this.folder.path.compare_to(other.folder.path);
    }

    private string get_default_icon_name() {
        var service_provider = this.folder.account.information.service_provider;

        switch (service_provider) {
        case Geary.ServiceProvider.GMAIL:
            return "tag-symbolic";
        default:
            return "folder-symbolic";
        }
    }

    private void update() {
        this.display_name = Util.I18n.to_folder_display_name(this.folder);

        switch (this.folder.used_as) {
        case INBOX:
            this.icon_name = "mail-inbox-symbolic";
            break;

        case DRAFTS:
            this.icon_name = "mail-drafts-symbolic";
            break;

        case SENT:
            this.icon_name = "mail-sent-symbolic";
            break;

        case FLAGGED:
            this.icon_name = "starred-symbolic";
            break;

        case IMPORTANT:
            this.icon_name = "task-due-symbolic";
            break;

        case ALL_MAIL:
        case ARCHIVE:
            this.icon_name = "mail-archive-symbolic";
            break;

        case JUNK:
            this.icon_name = "dialog-warning-symbolic";
            break;

        case TRASH:
            this.icon_name = "user-trash-symbolic";
            break;

        case OUTBOX:
            this.icon_name = "mail-outbox-symbolic";
            break;

        default:
            this.icon_name = get_default_icon_name();
            break;
        }

        switch (this.folder.used_as) {
        case DRAFTS:
        case OUTBOX:
            this.displayed_count = TOTAL;
            break;

        case INBOX:
        case JUNK:
        case NONE:
            this.displayed_count = UNREAD;
            break;

        default:
            this.displayed_count = NONE;
            break;
        }
    }

}
