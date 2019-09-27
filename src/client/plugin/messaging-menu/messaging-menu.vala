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
        typeof(Plugin.MessagingMenu)
    );
}

/** Updates the Unity messaging menu when new mail arrives. */
public class Plugin.MessagingMenu : Notification {


    public override GearyApplication application {
        get; construct set;
    }

    public override Application.NotificationContext context {
        get; construct set;
    }

    private global::MessagingMenu.App? app = null;


    public override void activate() {
        this.app = new global::MessagingMenu.App(
            "%s.desktop".printf(GearyApplication.APP_ID)
        );
        this.app.register();
        this.app.activate_source.connect(on_activate_source);

        this.context.folder_removed.connect(on_folder_removed);
        this.context.new_messages_arrived.connect(on_new_messages_changed);
        this.context.new_messages_retired.connect(on_new_messages_changed);
    }

    public override void deactivate(bool is_shutdown) {
        this.context.folder_removed.disconnect(on_folder_removed);
        this.context.new_messages_arrived.disconnect(on_new_messages_changed);
        this.context.new_messages_retired.disconnect(on_new_messages_changed);

        this.app.activate_source.disconnect(on_activate_source);
        this.app.unregister();
        this.app = null;
    }

    private string get_source_id(Geary.Folder folder) {
        return "new-messages-id-%s-%s".printf(folder.account.information.id, folder.path.to_string());
    }

    private void on_activate_source(string source_id) {
        foreach (Geary.Folder folder in this.context.get_folders()) {
            if (source_id == get_source_id(folder)) {
                this.application.show_folder.begin(folder);
                break;
            }
        }
    }

    private void on_new_messages_changed(Geary.Folder folder, int count) {
        if (count > 0) {
            show_new_messages_count(folder, count);
        } else {
            remove_new_messages_count(folder);
        }
    }

    private void on_folder_removed(Geary.Folder folder) {
        remove_new_messages_count(folder);
    }

    private void show_new_messages_count(Geary.Folder folder, int count) {
        if (this.context.should_notify_new_messages(folder)) {
            string source_id = get_source_id(folder);

            if (this.app.has_source(source_id)) {
                this.app.set_source_count(source_id, count);
            } else {
                this.app.append_source_with_count(
                    source_id,
                    null,
                    _("%s — New Messages").printf(folder.account.information.display_name),
                    count);
            }

            this.app.draw_attention(source_id);
        }
    }

    private void remove_new_messages_count(Geary.Folder folder) {
        string source_id = get_source_id(folder);
        if (this.app.has_source(source_id)) {
            this.app.remove_attention(source_id);
            this.app.remove_source(source_id);
        }
    }

}
