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
        typeof(Plugin.NotificationBadge)
    );
}

/** Updates Unity application badge with total new message count. */
public class Plugin.NotificationBadge : Notification {


    public override GearyApplication application {
        get; construct set;
    }

    public override Application.NotificationContext context {
        get; construct set;
    }

    private Unity.LauncherEntry? entry = null;

    public override void activate() {
        this.entry = Unity.LauncherEntry.get_for_desktop_id(
            GearyApplication.APP_ID + ".desktop"
        );
        this.context.notify["total-new-messages"].connect(on_total_changed);
        update_count();
    }

    public override void deactivate(bool is_shutdown) {
        this.context.notify["total-new-messages"].disconnect(on_total_changed);
        this.entry = null;
    }

    private void update_count() {
        int count = this.context.total_new_messages;
        this.entry.count = count;
        this.entry.count_visible = (count > 0);
    }

    private void on_total_changed() {
        update_count();
    }

}
