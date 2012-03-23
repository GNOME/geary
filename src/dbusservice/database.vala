/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

namespace Geary.DBus {

public uint db_email_hash(Geary.Email key) {
    return key.id.to_hash();
}

public bool db_email_equal(Geary.Email a, Geary.Email b) {
    return a.id.equals(b.id);
}

}

public class Geary.DBus.Database : Object {
    
    public static Database instance { get; private set; }
    
    private const string DBUS_PATH_PROP = "dbus-path";
    private const string DBUS_REG_PROP = "dbus-registration";
    
    private Gee.HashMap<ObjectPath, Object> path_to_object = 
        new Gee.HashMap<ObjectPath, Object>();
    
    // This is for tracking conversations.
    // TODO: find a better way to give conversations unique IDs.
    private int counter = 0;
    
    private Database() {
    }
    
    // Must call this to init the database.
    public static void init() {
        instance = new Geary.DBus.Database();
    }
    
    // Finds the conversation and returns the path.  If the conversation does not have
    // a path, it will be assigned one.
    public ObjectPath get_conversation_path(Geary.Conversation c, Geary.Folder folder) {
         ObjectPath? path = c.get_data(DBUS_PATH_PROP);
        
        if (path == null) {
            // Assign new path based on counter.
            path = new ObjectPath(Controller.CONVERSATION_PATH_PREFIX + 
                (counter++).to_string());
            
            register_object(c, new Geary.DBus.Conversation(c, folder), path);
        }
        
        return path;
    }
    
    // Gets a path for an email object.  If one does not exist, it will be created.
    public ObjectPath get_email_path(Geary.Email e, Geary.Folder folder) {
        ObjectPath? path = e.get_data(DBUS_PATH_PROP);
        if (path == null) {
            // Generate a path and save it.
            path = new ObjectPath(Controller.EMAIL_PATH_PREFIX + e.id.to_string());
            register_object(e, new Geary.DBus.Email(folder, e), path);
        }
        
        return path;
    }
    
    // Registers an object with DBus and saves the path.
    // Uses generics to bypass Vala's dbus codegen warning.
    private void register_object<T>(Object object, T dbus_object, ObjectPath path) {
        try {
            uint reg_id = Controller.instance.connection.register_object(path, dbus_object);
            object.set_data(DBUS_PATH_PROP, path);
            object.set_data(DBUS_REG_PROP, reg_id.to_string());
            path_to_object.set(path, object);
        } catch (Error e) {
            warning("Could not register path: %s", path);
            debug("Error: %s", e.message);
        }
    }
    
    public void remove_by_path(ObjectPath path) {
        debug("Removing path: %s", path);
        Object? o = path_to_object.get(path);
        if (o == null) {
            warning("Unable to remove object: %s", path);
            return;
        }
        
        remove(o);
    }
    
    // Removes an object
    private void remove(Object object) {
        debug("removing object");
        assert(object != null);
        ObjectPath? path = object.get_data(DBUS_PATH_PROP);
        string? reg_id_s = object.get_data(DBUS_REG_PROP);
        if (path == null || reg_id_s == null) {
            warning("Unable to remove object");
            return;
        }
        
        uint reg_id = (uint) long.parse(reg_id_s);
        path_to_object.unset(path);
        Controller.instance.connection.unregister_object(reg_id);
    }
}

