/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class GearyApplication : YorbaApplication {
    // TODO: replace static strings with const strings when gettext is integrated properly
    public const string NAME = "Geary";
    public static string DESCRIPTION = _("Email Client");
    public const string VERSION = "0.0.0+trunk";
    public const string COPYRIGHT = "Copyright 2011 Yorba Foundation";
    public const string WEBSITE = "http://www.yorba.org";
    public static string WEBSITE_LABEL = _("Visit the Yorba web site");
    
    public const string[] AUTHORS = {
        "Jim Nelson <jim@yorba.org>",
        null
    };
    
    public const string LICENSE = """
Geary is free software; you can redistribute it and/or modify it under the 
terms of the GNU Lesser General Public License as published by the Free 
Software Foundation; either version 2.1 of the License, or (at your option) 
any later version.

Geary is distributed in the hope that it will be useful, but WITHOUT 
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public License for 
more details.

You should have received a copy of the GNU Lesser General Public License 
along with Geary; if not, write to the Free Software Foundation, Inc., 
51 Franklin St, Fifth Floor, Boston, MA  02110-1301 USA
""";
    
    public new static GearyApplication instance {
        get {
            if (_instance == null)
                _instance = new GearyApplication();
            
            return _instance;
        }
    }
    
    private static GearyApplication? _instance = null;
    
    private MainWindow main_window = new MainWindow();
    private Geary.EngineAccount? account = null;
    public Configuration config {
        get; private set;
    }
    
    private GearyApplication() {
        base (NAME, "geary", "org.yorba.geary");
    }
    
    public override int startup() {
        config = new Configuration(YorbaApplication.instance.get_install_dir() != null,
            YorbaApplication.instance.get_exec_dir().get_child("build/src/client").get_path());
        
        // Get saved credentials. If not present, ask user.
        string username = "";
        string? password = null;
        try {
            Gee.List<string> accounts = Geary.Engine.get_usernames();
            if (accounts.size > 0) {
                username = accounts.get(0);
                password = keyring_get_password(username);
            }
        } catch (Error e) {
            debug("Unable to fetch accounts. Error: %s", e.message);
        }
        
        if (password == null) {
            LoginDialog login = new LoginDialog(username);
            login.show();
            if (login.get_response() == Gtk.ResponseType.OK) {
                username = login.username;
                password = login.password;
                
                // TODO: check credentials before saving password in keyring.
                keyring_save_password(username, password);
            } else {
                return 1;
            }
        }
        
        Geary.Credentials cred = new Geary.Credentials("imap.gmail.com", username, password);
        
        try {
            account = Geary.Engine.open(cred);
        } catch (Error err) {
            error("Unable to open mail database for %s: %s", cred.user, err.message);
        }
        
        main_window.show_all();
        main_window.start(account);
        return 0;
    }
    
    public override void activate() {
        main_window.present();
    }
    
    public override void exiting(bool panicked) {
        main_window.destroy();
    }
}

