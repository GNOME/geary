/*
 * Copyright © 2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * Implementation of the folder extension context.
 */
internal class Application.FolderContext :
    Geary.BaseObject, Plugin.FolderContext {


    private unowned Client application;
    private FolderStoreFactory folders_factory;
    private Plugin.FolderStore folders;


    internal FolderContext(Client application,
                           FolderStoreFactory folders_factory) {
        this.application = application;
        this.folders_factory = folders_factory;
        this.folders = folders_factory.new_folder_store();
    }

    public async Plugin.FolderStore get_folders()
        throws Plugin.Error.PERMISSION_DENIED {
        return this.folders;
    }

    internal void destroy() {
        this.folders_factory.destroy_folder_store(this.folders);
    }

}
