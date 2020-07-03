/*
 * Copyright © 2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * Implementation of the email plugin extension context.
 */
internal class Application.EmailPluginContext :
    Geary.BaseObject, Plugin.EmailContext {


    private unowned Client application;
    private PluginManager.PluginGlobals globals;
    private PluginManager.PluginContext plugin;
    private Plugin.EmailStore email;


    internal EmailPluginContext(Client application,
                                PluginManager.PluginGlobals globals,
                                PluginManager.PluginContext plugin) {
        this.application = application;
        this.globals = globals;
        this.plugin = plugin;
        this.email = globals.email.new_email_store();
    }

    public async Plugin.EmailStore get_email_store()
        throws Plugin.Error.PERMISSION_DENIED {
        return this.email;
    }

    public void add_email_info_bar(Plugin.EmailIdentifier displayed,
                                    Plugin.InfoBar info_bar,
                                    uint priority) {
        Geary.EmailIdentifier? id = this.globals.email.to_engine_id(displayed);
        if (id != null) {
            foreach (MainWindow main in this.application.get_main_windows()) {
                if (main.conversation_viewer.current_list != null) {
                    main.conversation_viewer.current_list.add_email_info_bar(
                        id,
                        new Components.InfoBar.for_plugin(
                            info_bar,
                            this.plugin.action_group_name,
                            (int) priority
                        )
                    );
                }
            }
        }
    }

    public void remove_email_info_bar(Plugin.EmailIdentifier displayed,
                                      Plugin.InfoBar info_bar) {
        Geary.EmailIdentifier? id = this.globals.email.to_engine_id(displayed);
        if (id != null) {
            foreach (MainWindow main in this.application.get_main_windows()) {
                if (main.conversation_viewer.current_list != null) {
                    // XXX implement this
                    //main.conversation_viewer.current_list.remove_email_info_bar(
                    //    id,
                    //    XXX
                    //);
                }
            }
        }
    }

    internal void email_displayed(Geary.AccountInformation account,
                                  Geary.Email email) {
        AccountContext? context =
            this.application.controller.get_context_for_account(account);
        if (context != null) {
            this.email.email_displayed(
                this.globals.email.to_plugin_email(email, context)
            );
        }
    }

    internal void email_sent(Geary.AccountInformation account,
                             Geary.Email email) {
        AccountContext? context =
            this.application.controller.get_context_for_account(account);
        if (context != null) {
            this.email.email_sent(
                this.globals.email.to_plugin_email(email, context)
            );
        }
    }

    internal void destroy() {
        this.globals.email.destroy_email_store(this.email);
    }

}
