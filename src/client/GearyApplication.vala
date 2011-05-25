/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class GearyApplication : YorbaApplication {
    public static GearyApplication instance {
        get {
            if (_instance == null)
                _instance = new GearyApplication();
            
            return _instance;
        }
    }
    
    private static GearyApplication? _instance = null;
    
    private MainWindow main_window = new MainWindow();
    private Geary.Engine engine = new Geary.Engine();
    
    private GearyApplication() {
        base ("org.yorba.geary");
    }
    
    public override void startup() {
        main_window.show_all();
        main_window.login(engine, args[1], args[2]);
    }
    
    public override void activate() {
        main_window.present();
    }
    
    public override void exiting(bool panicked) {
        main_window.destroy();
    }
}

