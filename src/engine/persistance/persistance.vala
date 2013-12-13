/* Copyright 2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Object persistance is implemented for GObjects by serializing (saving) their properties
 * and deserializing (loading) them later.  Only properties are serialized/deserialized in this
 * implementation; a more sophisticated system could probably be coded later if necessary.
 *
 * NOTE: This is a simple first-step implementation that doesn't attempt full serialization of
 * an object containment tree.  It only performs "flat" persistance of an object.  What's more,
 * any properties it does not recognize must be manually persisted by the object itself.
 */

namespace Geary.Persistance {

private bool is_serializable(ParamSpec param_spec, bool warn) {
    if ((param_spec.flags & ParamFlags.READWRITE) == 0) {
        if (warn) {
            debug("%s type %s not read/write, cannot be serialized", param_spec.name,
                param_spec.value_type.name());
        }
        
        return false;
    } else if ((param_spec.flags & ParamFlags.CONSTRUCT_ONLY) != 0) {
        if (warn) {
            debug("%s type %s is construct-only, cannot be serialized", param_spec.name,
                param_spec.value_type.name());
        }
        
        return false;
    }
    
    return true;
}

}

