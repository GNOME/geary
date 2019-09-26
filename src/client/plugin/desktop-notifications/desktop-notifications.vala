/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2019 Michael Gratton <mike@vee.net>.
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
public class Plugin.DesktopNotifications : Notification {


    public const Geary.Email.Field REQUIRED_FIELDS =
        Geary.Email.Field.ORIGINATORS | Geary.Email.Field.SUBJECT;

    public override GearyApplication application {
        get; construct set;
    }

    public override Application.NotificationContext context {
        get; construct set;
    }

    private const string ARRIVED_ID = "email-arrived";

    private GLib.Notification? arrived_notification = null;
    private GLib.Cancellable? cancellable = null;


    public override void activate() {
        this.context.add_required_fields(REQUIRED_FIELDS);
        this.context.new_messages_arrived.connect(on_new_messages_arrived);
        this.cancellable = new GLib.Cancellable();
    }

    public override void deactivate(bool is_shutdown) {
        this.cancellable.cancel();
        this.context.new_messages_arrived.disconnect(on_new_messages_arrived);
        this.context.remove_required_fields(REQUIRED_FIELDS);

        // Keep existing notifications if shutting down since they are
        // persistent, but revoke if the plugin is being disabled.
        if (!is_shutdown) {
            clear_arrived_notification();
        }
    }

    private void clear_arrived_notification() {
        this.application.withdraw_notification(ARRIVED_ID);
        this.arrived_notification = null;
    }

    private void notify_new_mail(Geary.Folder folder, int added) {
        string body = ngettext(
            /// Notification body text for new email when no other
            /// new messages are already awaiting.
            "%d new message", "%d new messages", added
        ).printf(added);

        int total = 0;
        try {
            total = this.context.get_new_message_count(folder);
        } catch (Geary.EngineError err) {
            // All good
        }

        if (total > added) {
            body = ngettext(
                /// Notification body text for new email when
                /// other new messages have already been notified
                /// about
                "%s, %d new message total", "%s, %d new messages total",
                total
            ).printf(body, total);
        }

        issue_arrived_notification(
            folder.account.information.display_name, body, folder, null
        );
    }

    private async void notify_one_message(Geary.Folder folder,
                                          Geary.Email email,
                                          GLib.Cancellable? cancellable)
        throws GLib.Error {
        Geary.RFC822.MailboxAddress? originator =
            Util.Email.get_primary_originator(email);
        if (originator != null) {
            Application.ContactStore contacts =
                this.context.get_contact_store(folder.account);
            Application.Contact contact = yield contacts.load(
                originator, cancellable
            );

            int count = 1;
            try {
                count = this.context.get_new_message_count(folder);
            } catch (Geary.EngineError.NOT_FOUND err) {
                // All good
            }

            string body = "";
            if (count <= 1) {
                body = Util.Email.strip_subject_prefixes(email);
            } else {
                body = ngettext(
                    "%s\n(%d other new message for %s)",
                    "%s\n(%d other new messages for %s)", count - 1).printf(
                        Util.Email.strip_subject_prefixes(email),
                        count - 1,
                        folder.account.information.display_name
                    );
            }

            issue_arrived_notification(
                contact.is_trusted
                ? contact.display_name : originator.to_short_display(),
                body,
                folder,
                email.id
            );
        } else {
            notify_new_mail(folder, 1);
        }
    }

    private void issue_arrived_notification(string summary,
                                            string body,
                                            Geary.Folder folder,
                                            Geary.EmailIdentifier? id) {
        // only one outstanding notification at a time
        clear_arrived_notification();

        string? action = null;
        GLib.Variant[] target_param = new GLib.Variant[] {
            folder.account.information.id,
            new GLib.Variant.variant(folder.path.to_variant())
        };

        if (id == null) {
            action = GearyApplication.ACTION_SHOW_FOLDER;
        } else {
            action = GearyApplication.ACTION_SHOW_EMAIL;
            target_param += new GLib.Variant.variant(id.to_variant());
        }

        this.arrived_notification = issue_notification(
            ARRIVED_ID,
            summary,
            body,
            "app." + action,
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
            new GLib.ThemedIcon("%s-symbolic".printf(GearyApplication.APP_ID))
        );

        /* We do not show notification action under Unity */

        if (this.application.config.desktop_environment == Configuration.DesktopEnvironment.UNITY) {
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

    private void on_new_messages_arrived(Geary.Folder folder,
                                         int total,
                                         int added) {
        if (this.context.should_notify_new_messages(folder)) {
            if (added == 1 &&
                this.context.last_new_message_folder != null &&
                this.context.last_new_message != null) {
                this.notify_one_message.begin(
                    this.context.last_new_message_folder,
                    this.context.last_new_message,
                    this.cancellable
                );
            } else if (added > 0) {
                notify_new_mail(folder, added);
            }
        }
    }

}
