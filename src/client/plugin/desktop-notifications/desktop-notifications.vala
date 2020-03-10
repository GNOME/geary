/*
 * Copyright © 2016 Software Freedom Conservancy Inc.
 * Copyright © 2019-2020 Michael Gratton <mike@vee.net>.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

[ModuleInit]
public void peas_register_types(TypeModule module) {
    Peas.ObjectModule obj = module as Peas.ObjectModule;
    obj.register_extension_type(
        typeof(Plugin.Notification),
        typeof(Plugin.DesktopNotifications)
    );
}

/**
 * Manages standard desktop application notifications.
 */
public class Plugin.DesktopNotifications : Geary.BaseObject, Notification {


    private const Geary.SpecialFolderType[] MONITORED_TYPES = {
        INBOX, NONE
    };

    public global::Application.NotificationContext notifications {
        get; set;
    }

    private const string ARRIVED_ID = "email-arrived";

    private global::Application.Client? application = null;
    private EmailStore? email = null;
    private GLib.Notification? arrived_notification = null;
    private GLib.Cancellable? cancellable = null;


    public override void activate() {
        try {
            this.application = this.notifications.get_client_application();
        } catch (GLib.Error error) {
            warning(
                "Failed obtain application instance: %s",
                error.message
            );
        }

        this.notifications.new_messages_arrived.connect(on_new_messages_arrived);
        this.cancellable = new GLib.Cancellable();

        this.connect_signals.begin();
    }

    public override void deactivate(bool is_shutdown) {
        this.cancellable.cancel();

        // Keep existing notifications if shutting down since they are
        // persistent, but revoke if the plugin is being disabled.
        if (!is_shutdown) {
            clear_arrived_notification();
        }
    }

    private async void connect_signals() {
        try {
            this.email = yield this.notifications.get_email();
        } catch (GLib.Error error) {
            warning(
                "Unable to get folders for plugin: %s",
                error.message
            );
        }

        try {
            FolderStore folders = yield this.notifications.get_folders();
            folders.folders_available.connect(
                (folders) => check_folders(folders)
            );
            folders.folders_unavailable.connect(
                (folders) => check_folders(folders)
            );
            folders.folders_type_changed.connect(
                (folders) => check_folders(folders)
            );
            check_folders(folders.get_folders());
        } catch (GLib.Error error) {
            warning(
                "Unable to get folders for plugin: %s",
                error.message
            );
        }
    }

    private void clear_arrived_notification() {
        this.application.withdraw_notification(ARRIVED_ID);
        this.arrived_notification = null;
    }

    private async void notify_specific_message(Folder folder,
                                               int total,
                                               Email email
    ) throws GLib.Error {
        string title = to_notitication_title(folder.account, total);
        Geary.RFC822.MailboxAddress? originator = email.get_primary_originator();
        if (originator != null) {
            ContactStore contacts =
                yield this.notifications.get_contacts_for_folder(folder);
            global::Application.Contact? contact = yield contacts.load(
                originator, this.cancellable
            );
            title = (
                contact.is_trusted
                ? contact.display_name
                : originator.to_short_display()
            );
        }

        string body = email.subject;
        if (total > 1) {
            body = ngettext(
                /// Notification body when a message as been received
                /// and other unread messages have not been
                /// seen. First string substitution is the message
                /// subject, second is the number of unseen messages,
                /// third is the name of the email account.
                "%s\n(%d other new message for %s)",
                "%s\n(%d other new messages for %s)",
                total - 1
            ).printf(
                body,
                total - 1,
                folder.account.display_name
            );
        }

        issue_arrived_notification(title, body, folder, email.identifier);
    }

    private void notify_general(Folder folder, int total, int added) {
        string title = to_notitication_title(folder.account, total);
        string body = ngettext(
            /// Notification body when multiple messages have been
            /// received at the same time and other unseen messages
            /// exist. String substitution is the number of new
            /// messages that have arrived.
            "%d new message", "%d new messages", added
        ).printf(added);
        if (total > added) {
            body = ngettext(
                /// Notification body when multiple messages have been
                /// received at the same time and some unseen messages
                /// already exist. String substitution is the message
                /// above with the number of new messages that have
                /// arrived, number substitution is the total number
                /// of unseen messages.
                "%s, %d new message total", "%s, %d new messages total",
                total
            ).printf(body, total);
        }

        issue_arrived_notification(title, body, folder, null);
    }

    private void issue_arrived_notification(string summary,
                                            string body,
                                            Folder folder,
                                            EmailIdentifier? id) {
        // only one outstanding notification at a time
        clear_arrived_notification();

        string? action = null;
        GLib.Variant[] target_param = new GLib.Variant[] {
            new GLib.Variant.variant(folder.to_variant())
        };

        if (id == null) {
            action = Action.Application.SHOW_FOLDER;
        } else {
            action = Action.Application.SHOW_EMAIL;
            target_param += new GLib.Variant.variant(id.to_variant());
        }

        this.arrived_notification = issue_notification(
            ARRIVED_ID,
            summary,
            body,
            Action.Application.prefix(action),
            new GLib.Variant.tuple(target_param)
        );
    }

    private GLib.Notification issue_notification(string id,
                                                 string summary,
                                                 string body,
                                                 string? action,
                                                 GLib.Variant? action_target) {
        GLib.Notification notification = new GLib.Notification(summary);
        notification.set_body(body);
        notification.set_icon(
            new GLib.ThemedIcon(
                "%s-symbolic".printf(global::Application.Client.APP_ID)
            )
        );

        // Do not show notification actions under Unity, it's
        // notifications daemon doesn't support them.
        if (this.application.config.desktop_environment == UNITY) {
            this.application.send_notification(id, notification);
            return notification;
        } else {
            if (action != null) {
                notification.set_default_action_and_target_value(
                    action, action_target
                );
            }

            this.application.send_notification(id, notification);
            return notification;
        }
    }

    private async void handle_new_messages(Folder folder,
                                           int total,
                                           Gee.Collection<EmailIdentifier> added) {
        if (this.notifications.should_notify_new_messages(folder)) {
            // notify about a specific message if it's the only one
            // present and it can be loaded, otherwise notify
            // generally
            bool notified = false;
            if (this.email != null &&
                added.size == 1) {
                try {
                    Email? message = Geary.Collection.first(
                        yield this.email.get_email(added, this.cancellable)
                    );
                    if (message != null) {
                        yield notify_specific_message(folder, total, message);
                        notified = true;
                    } else {
                        warning("Could not load email for notification");
                    }
                } catch (GLib.Error error) {
                    warning("Error loading email for notification: %s", error.message);
                }
            }

            if (!notified) {
                notify_general(folder, total, added.size);
            }
        }
    }

    private void check_folders(Gee.Collection<Folder> folders) {
        foreach (Folder folder in folders) {
            if (folder.folder_type in MONITORED_TYPES) {
                this.notifications.start_monitoring_folder(folder);
            } else {
                this.notifications.stop_monitoring_folder(folder);
            }
        }
    }

    private inline string to_notitication_title(Account account, int count) {
        return ngettext(
            /// Notification title when new messages have been
            /// received. String substitution is the name of the email
            /// account.
            "New message for %s", "New messages for %s", count
        ).printf(account.display_name);
    }

    private void on_new_messages_arrived(Folder folder,
                                         int total,
                                         Gee.Collection<EmailIdentifier> added) {
        this.handle_new_messages.begin(folder, total, added);
    }

}
