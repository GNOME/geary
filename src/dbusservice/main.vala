/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

int main(string[] args) {
    if (args.length != 3) {
        stderr.printf("Geary D-Bus daemon\n");
        stderr.printf("Usage: gearyd <username> <password>\n");
        
        return 1;
    }
    
    debug("Starting Gearyd...");
    Geary.DBus.Controller.init(args);
    Geary.DBus.Controller.instance.start.begin();
    
    debug("Entering main loop");
    new MainLoop().run();
    
    return 0;
}
