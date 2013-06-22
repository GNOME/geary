/* Copyright 2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

namespace Geary.ObjectUtils {

/**
 * Creates a set of property bindings from source to dest with the given binding flags.
 */
public Gee.List<Binding>? mirror_properties(Object source, Object dest, BindingFlags 
    flags = GLib.BindingFlags.DEFAULT | GLib.BindingFlags.SYNC_CREATE) {
    // Make sets of both object's properties.
    Gee.HashSet<ParamSpec> source_properties = new Gee.HashSet<ParamSpec>();
    source_properties.add_all_array(source.get_class().list_properties());
    Gee.HashSet<ParamSpec> dest_properties = new Gee.HashSet<ParamSpec>();
    dest_properties.add_all_array(dest.get_class().list_properties());
    
    // Remove properties from source_properties that are not in both sets.
    source_properties.retain_all(dest_properties);
    
    // Create all bindings.
    Gee.List<Binding> bindings = new Gee.ArrayList<Binding>();
    foreach(ParamSpec ps in source_properties)
        bindings.add(source.bind_property(ps.name, dest, ps.name, flags));
    
    return bindings.size > 0 ? bindings : null;
}

/**
 * Removes a property mirror created by mirror_properties
 */
public void unmirror_properties(Gee.List<Binding> bindings) {
    foreach(Binding b in bindings)
        b.unref();
    
    bindings.clear();
}

}

