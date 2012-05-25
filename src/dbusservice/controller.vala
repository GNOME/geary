/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.DBus.Controller {
    public static const string CONVERSATION_PATH_PREFIX = "/org/yorba/geary/conversation/";
    public static const string EMAIL_PATH_PREFIX = "/org/yorba/geary/email/";
    
    public static Geary.DBus.Controller instance { get; private set; }
    
    public DBusConnection connection { get; private set; }
    
    private string[] args;
    private Geary.EngineAccount account;
    private Geary.DBus.Conversations conversations;
    
    public static void init(string[] args) {
        instance = new Geary.DBus.Controller(args);
        Database.init();
    }
    
    protected Controller(string[] args) {
        this.args = args;
    }
    
    public async void start() {
        try {
            Geary.Engine.init(get_user_data_directory(), get_resource_directory());
            
            connection = yield Bus.get(GLib.BusType.SESSION);
            
            // Open the account.
            Geary.Credentials credentials = new Geary.Credentials(args[1], args[2]);
            Geary.AccountInformation account_information = new Geary.AccountInformation(credentials);
            account_information.load_info_from_file();
            account = account_information.get_account();
            account.report_problem.connect(on_report_problem);
            
            // Open the Inbox folder.
            Geary.SpecialFolderMap? special_folders = account.get_special_folder_map();
            Geary.Folder folder = yield account.fetch_folder_async(special_folders.get_folder(
                Geary.SpecialFolderType.INBOX).path);
            
            yield folder.open_async(false, null);
            
            conversations = new Geary.DBus.Conversations(folder);
            
            // Register interfaces.
            Bus.own_name(BusType.SESSION, Geary.DBus.Conversations.INTERFACE_NAME, BusNameOwnerFlags.NONE,
                on_conversations_aquired);
            Bus.own_name(BusType.SESSION, Geary.DBus.Conversation.INTERFACE_NAME, BusNameOwnerFlags.NONE);
            Bus.own_name(BusType.SESSION, Geary.DBus.Email.INTERFACE_NAME, BusNameOwnerFlags.NONE);
        } catch (Error e) {
            debug("Startup error: %s", e.message);
            return;
        }
    }
    
    public File get_user_data_directory() {
        return File.new_for_path(Environment.get_user_data_dir()).get_child("geary");
    }
    
    public File get_resource_directory() {
        return File.new_for_path(Environment.get_current_dir());
    }
    
    private void on_report_problem(Geary.Account.Problem problem, Geary.Credentials? credentials,
        Error? err) {
        debug("Reported problem: %s Error: %s", problem.to_string(), err != null ? err.message : "(N/A)");
    }
    
    private void on_conversations_aquired(DBusConnection c) {
        try {
            connection.register_object("/org/yorba/geary/conversations", conversations);
        } catch (IOError e) {
            debug("Error: %s", e.message);
        }
    }
}

