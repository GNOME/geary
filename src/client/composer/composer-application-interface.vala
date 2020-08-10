/*
 * Copyright © 2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */


/**
 * Provides access to application objects and services to the composer.
 *
 * This interface defines the composer's requirements for integrating
 * with the application and enables the composer to be unit tested
 * without having to load the complete application.
 */
internal interface Composer.ApplicationInterface :
    GLib.Object, Application.AccountInterface {


    public abstract void report_problem(Geary.ProblemReport report);

    internal abstract async void send_composed_email(Composer.Widget composer);

    internal abstract async void save_composed_email(Composer.Widget composer);

    internal abstract async void discard_composed_email(Composer.Widget composer);

}
