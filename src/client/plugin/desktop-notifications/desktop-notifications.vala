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
        typeof(Plugin.PluginBase),
        typeof(Plugin.DesktopNotifications)
    );
}

/**
 * Manages standard desktop application notifications.
 */
public class Plugin.DesktopNotifications :
    PluginBase,
    NotificationExtension,
    FolderExtension,
    EmailExtension,
    TrustedExtension {


    private const Geary.Folder.SpecialUse[] MONITORED_TYPES = {
        INBOX, NONE
    };

    public NotificationContext notifications {
        get; set construct;
    }

    public FolderContext folders {
        get; set construct;
    }

    public EmailContext email {
        get; set construct;
    }

    public global::Application.Client client_application {
        get; set construct;
    }

    public global::Application.PluginManager client_plugins {
        get; set construct;
    }

    private const string ARRIVED_ID = "email-arrived";

    private EmailStore? email_store = null;
    private GLib.Notification? arrived_notification = null;
    private GLib.Cancellable? cancellable = null;


    public override async void activate(bool is_startup) throws GLib.Error {
        this.cancellable = new GLib.Cancellable();
        this.email_store = yield this.email.get_email_store();

        this.notifications.new_messages_arrived.connect(on_new_messages_arrived);
        this.notifications.new_messages_retired.connect(on_new_messages_retired);

        FolderStore folder_store = yield this.folders.get_folder_store();
        folder_store.folders_available.connect(
            (folders) => check_folders(folders)
        );
        folder_store.folders_unavailable.connect(
                (folders) => check_folders(folders)
        );
        folder_store.folders_type_changed.connect(
            (folders) => check_folders(folders)
        );
        check_folders(folder_store.get_folders());
    }

    public override async void deactivate(bool is_shutdown) throws GLib.Error {
        this.cancellable.cancel();

        // Keep existing notifications if shutting down since they are
        // persistent, but revoke if the plugin is being disabled.
        if (!is_shutdown) {
            clear_arrived_notification();
        }
    }

    private void clear_arrived_notification() {
        this.client_application.withdraw_notification(ARRIVED_ID);
        this.arrived_notification = null;
    }

    private async void notify_specific_message(Folder folder,
                                               int total,
                                               Email email
    ) throws GLib.Error {
        string title = to_notitication_title(folder.account, total);
        GLib.Icon icon = null;
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

            icon = contact.avatar;
        }

        string body = Util.Email.strip_subject_prefixes(email);
        if (total > 1) {
            body = ngettext(
                /// Notification body when a message as been received
                /// and other unread messages have not been
                /// seen. First string substitution is the message
                /// subject and the second is the number of unseen
                /// messages
                "%s\n(%d other new message)",
                "%s\n(%d other new messages)",
                total - 1
            ).printf(
                body,
                total - 1
            );
        }

        int window_scale = 1;
        Gdk.Display? display = Gdk.Display.get_default();
        if (display != null) {
          Gdk.Monitor? monitor = display.get_primary_monitor();
          if (monitor != null) {
            window_scale = monitor.scale_factor;
          }
        }

        var avatar = new Hdy.Avatar(32, title, true);
        avatar.loadable_icon = icon as GLib.LoadableIcon;
        icon = yield avatar.draw_to_pixbuf_async(32, window_scale, null);

        issue_arrived_notification(title, body, icon, folder, email.identifier);
    }

    private void notify_general(Folder folder, int total, int added) {
        GLib.Icon icon = new GLib.ThemedIcon("%s-symbolic".printf(global::Application.Client.APP_ID));
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
                "%s, %d new message total",
                "%s, %d new messages total",
                total
            ).printf(body, total);
        }

        issue_arrived_notification(title, body, icon, folder, null);
    }

    private void issue_arrived_notification(string summary,
                                            string body,
                                            GLib.Icon icon,
                                            Folder folder,
                                            EmailIdentifier? id) {
        // only one outstanding notification at a time
        clear_arrived_notification();

        string? action = null;
        GLib.Variant? target_param = null;
        if (id == null) {
            action = Action.Application.SHOW_FOLDER;
            target_param = folder.to_variant();
        } else {
            action = Action.Application.SHOW_EMAIL;
            target_param = id.to_variant();
        }

        this.arrived_notification = issue_notification(
            ARRIVED_ID,
            summary,
            body,
            icon,
            Action.Application.prefix(action),
            target_param
        );
    }

    private GLib.Notification issue_notification(string id,
                                                 string summary,
                                                 string body,
                                                 GLib.Icon icon,
                                                 string? action,
                                                 GLib.Variant? action_target) {
        GLib.Notification notification = new GLib.Notification(summary);
        notification.set_body(body);
        notification.set_icon(icon);

        // Do not show notification actions under Unity, it's
        // notifications daemon doesn't support them.
        if (this.client_application.config.desktop_environment == UNITY) {
            this.client_application.send_notification(id, notification);
            return notification;
        } else {
            if (action != null) {
                notification.set_default_action_and_target_value(
                    action, action_target
                );
            }

            this.client_application.send_notification(id, notification);
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
            try {
                Email? message = Geary.Collection.first(
                    yield this.email_store.get_email(
                        Geary.Collection.single(Geary.Collection.first(added)),
                        this.cancellable
                    )
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

            if (!notified) {
                notify_general(folder, total, added.size);
            }
        }
    }

    private void check_folders(Gee.Collection<Folder> folders) {
        foreach (Folder folder in folders) {
            if (folder.used_as in MONITORED_TYPES) {
                this.notifications.start_monitoring_folder(folder);
            } else {
                this.notifications.stop_monitoring_folder(folder);
            }
        }
    }

    private inline string to_notitication_title(Account account, int count) {
        return ngettext(
            /// Notification title when new messages have been
            /// received
            "New message", "New messages", count
        );
    }

    private void on_new_messages_arrived(Folder folder,
                                         int total,
                                         Gee.Collection<EmailIdentifier> added) {
        this.handle_new_messages.begin(folder, total, added);
    }

    private void on_new_messages_retired(Folder folder, int total) {
        clear_arrived_notification();
    }

}
