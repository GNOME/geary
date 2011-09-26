/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.State.Machine {
    private Geary.State.MachineDescriptor descriptor;
    private uint state;
    private Mapping[,] transitions;
    private unowned Transition? default_transition;
    private bool locked = false;
    private bool abort_on_no_transition = true;
    private bool logging = false;
    
    public Machine(MachineDescriptor descriptor, Mapping[] mappings, Transition? default_transition) {
        this.descriptor = descriptor;
        this.default_transition = default_transition;
        
        // verify that each state and event in the mappings are valid
        foreach (Mapping mapping in mappings) {
            assert(mapping.state < descriptor.state_count);
            assert(mapping.event < descriptor.event_count);
        }
        
        state = descriptor.start_state;
        
        // build a transition map with state/event IDs (i.e. offsets) pointing directly into the
        // map
        transitions = new Mapping[descriptor.state_count, descriptor.event_count];
        for (int ctr = 0; ctr < mappings.length; ctr++) {
            Mapping mapping = mappings[ctr];
            assert(transitions[mapping.state, mapping.event] == null);
            transitions[mapping.state, mapping.event] = mapping;
        }
    }
    
    public uint get_state() {
        return state;
    }
    
    public bool get_abort_on_no_transition() {
        return abort_on_no_transition;
    }
    
    public void set_abort_on_no_transition(bool abort) {
        abort_on_no_transition = abort;
    }
    
    public void set_logging(bool logging) {
        this.logging = logging;
    }
    
    public bool is_logging() {
        return logging;
    }
    
    public uint issue(uint event, void *user = null, Object? object = null, Error? err = null) {
        assert(event < descriptor.event_count);
        assert(state < descriptor.state_count);
        
        unowned Mapping? mapping = transitions[state, event];
        
        unowned Transition? transition = (mapping != null) ? mapping.transition : default_transition;
        if (transition == null) {
            string msg = "%s: No transition defined for %s@%s".printf(to_string(),
                descriptor.get_event_string(event), descriptor.get_state_string(state));
            
            if (get_abort_on_no_transition())
                error(msg);
            else
                critical(msg);
            
            return state;
        }
        
        // guard against reentrancy ... don't want to use a non-reentrant lock because then
        // the machine will simply hang; assertion is better to ferret out design flaws
        assert(!locked);
        locked = true;
        
        uint old_state = state;
        state = transition(state, event, user, object, err);
        assert(state < descriptor.state_count);
        
        assert(locked);
        locked = false;
        
        if (is_logging()) {
            message("%s: %s@%s -> %s", to_string(), descriptor.get_event_string(event),
                descriptor.get_state_string(old_state), descriptor.get_state_string(state));
        }
        
        return state;
    }
    
    public string get_state_string(uint state) {
        return descriptor.get_state_string(state);
    }
    
    public string get_event_string(uint event) {
        return descriptor.get_event_string(event);
    }
    
    public string to_string() {
        return "Machine %s [%s]".printf(descriptor.name, descriptor.get_state_string(state));
    }
}

