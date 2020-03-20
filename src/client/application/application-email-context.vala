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


    internal EmailContext(Client application,
                          EmailStoreFactory email_factory) {
        this.application = application;
        this.email_factory = email_factory;
        this.email = email_factory.new_email_store();
    }

    public async Plugin.EmailStore get_email()
        throws Plugin.Error.PERMISSION_DENIED {
        return this.email;
    }

    internal void destroy() {
        this.email_factory.destroy_email_store(this.email);
    }

}
