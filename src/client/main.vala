/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

int main(string[] args) {
    // initialize GTK, which modifies the command-line arguments
    Gtk.init(ref args);
    
    try {
        // if already registered, silently exit
        if (!GearyApplication.instance.register())
            return 0;
    } catch (Error err) {
        stderr.printf("Unable to register application: %s", err.message);
        
        return 1;
    }
    
    return GearyApplication.instance.run(args);
}

