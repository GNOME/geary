/*
 * Copyright © 2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * Implementation of the email plugin extension context.
 */
internal class Application.EmailContext :
    Geary.BaseObject, Plugin.EmailContext {


    private unowned Client application;
    private EmailStoreFactory email_factory;
    private Plugin.EmailStore email;
    private string action_group_name;


    internal EmailContext(Client application,
                          EmailStoreFactory email_factory,
                          string action_group_name) {
        this.application = application;
        this.email_factory = email_factory;
        this.email = email_factory.new_email_store();
        this.action_group_name = action_group_name;
    }

    public async Plugin.EmailStore get_email()
        throws Plugin.Error.PERMISSION_DENIED {
        return this.email;
    }

    public void add_email_info_bar(Plugin.EmailIdentifier displayed,
                                    Plugin.InfoBar info_bar,
                                    uint priority) {
        Geary.EmailIdentifier? id = this.email_factory.to_engine_id(displayed);
        if (id != null) {
            foreach (MainWindow main in this.application.get_main_windows()) {
                if (main.conversation_viewer.current_list != null) {
                    main.conversation_viewer.current_list.add_email_info_bar(
                        id,
                        new Components.InfoBar.for_plugin(
                            info_bar, this.action_group_name
                        )
                    );
                }
            }
        }
    }

    public void remove_email_info_bar(Plugin.EmailIdentifier displayed,
                                      Plugin.InfoBar info_bar) {
        Geary.EmailIdentifier? id = this.email_factory.to_engine_id(displayed);
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
        this.email.email_displayed(
            this.email_factory.to_plugin_email(email, account)
        );
    }

    internal void email_sent(Geary.AccountInformation account,
                             Geary.Email email) {
        this.email.email_sent(
            this.email_factory.to_plugin_email(email, account)
        );
    }

    internal void destroy() {
        this.email_factory.destroy_email_store(this.email);
    }

}
