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
    private Geary.Account account;
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
            // TODO: Don't assume username is email, allow separate imap/smtp credentials.
            Geary.AccountInformation account_information = Geary.Engine.get_account_for_email(args[1]);
            account_information.imap_credentials = new Geary.Credentials(args[1], args[2]);
            account_information.smtp_credentials = new Geary.Credentials(args[1], args[2]);
            
            // convert AccountInformation into an Account
            try {
                account = account_information.get_account();
            } catch (EngineError err) {
                error("Problem loading account from account information: %s", err.message);
            }

            account.report_problem.connect(on_report_problem);
            
            // Open the Inbox folder.
            Geary.Folder? folder = null;
            Gee.Collection<Geary.Folder> folders = yield account.list_folders_async(null, null);
            foreach(Geary.Folder folder_to_check in folders) {
                if(folder_to_check.get_special_folder_type() == Geary.SpecialFolderType.INBOX) {
                    folder = folder_to_check;
                    break;
                }
            }
            
            if (folder == null) {
                warning("No inbox folder found");
                return;
            }
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
    
    private void on_report_problem(Geary.Account.Problem problem, Geary.AccountSettings settings,
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

