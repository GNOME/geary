/*
 * Copyright © 2020 Michael Gratton <mike@vee.net>.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

[ModuleInit]
public void peas_register_types(TypeModule module) {
    Peas.ObjectModule obj = module as Peas.ObjectModule;
    obj.register_extension_type(
        typeof(Plugin.PluginBase),
        typeof(Plugin.SentSound)
    );
}

/** Plays the desktop sent-mail sound when an email is sent. */
public class Plugin.SentSound : PluginBase, EmailExtension {


    public EmailContext email {
        get; set construct;
    }


    private GSound.Context? context = null;
    private EmailStore? store = null;


    public override async void activate(bool is_startup) throws GLib.Error {
        this.context = new GSound.Context();
        this.context.init();

        this.store = yield this.email.get_email_store();
        this.store.email_sent.connect(on_sent);

        if (!is_startup) {
            play_sound();
        }
    }

    public override async void deactivate(bool is_shutdown) throws GLib.Error {
        this.store.email_sent.disconnect(on_sent);
        this.store = null;

        this.context = null;
    }

    private void play_sound() {
        try {
            this.context.play_simple(
                null, GSound.Attribute.EVENT_ID, "message-sent-email"
            );
        } catch (GLib.Error err) {
            warning("Failed to play sent mail sound: %s", err.message);
            this.plugin_application.report_problem(
                new Geary.ProblemReport(err)
            );
        }
    }

    private void on_sent() {
        play_sound();
    }

}
