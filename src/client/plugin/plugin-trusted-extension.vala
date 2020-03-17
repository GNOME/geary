/*
 * Copyright © 2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * A plugin extension point for trusted plugins.
 *
 * In-tree plugins may implement this interface if they require access
 * to the client application's internal machinery.
 *
 * Since the client application and engine objects have no API
 * stability guarantee, Geary will refuse to load out-of-tree plugins
 * that implement this extension point.
 */
public interface Plugin.TrustedExtension : PluginBase {

    /**
     * Client application object.
     *
     * This will be set during (or just after) plugin construction,
     * before {@link PluginBase.activate} is called.
     */
    public abstract global::Application.Client client_application {
        get; set construct;
    }

    /**
     * Client plugin manager object.
     *
     * This will be set during (or just after) plugin construction,
     * before {@link PluginBase.activate} is called.
     */
    public abstract global::Application.PluginManager client_plugins {
        get; set construct;
    }

}
