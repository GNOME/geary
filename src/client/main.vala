/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

int main(string[] args) {
    GearyApplication app = new GearyApplication();
    
    int ec = app.run(args);
    
#if REF_TRACKING
    Geary.BaseObject.dump_refs(stdout);
#endif
    
    return ec;
}

