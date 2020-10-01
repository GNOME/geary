/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class Geary.State.Machine : BaseObject {

    /** The state machine's current state. */
    public uint state { get; private set; }

    /** Determines if the state machine crashes your app when mis-configured. */
    public bool abort_on_no_transition { get; set; default = true; }

    /** Determines if transition logging is enabled. */
    public bool logging { get; private set; default = false; }

    private Geary.State.MachineDescriptor descriptor;
    private Mapping[,] transitions;
    private unowned Transition? default_transition;
    private bool locked = false;
    private unowned PostTransition? post_transition = null;
    private void *post_user = null;
    private Object? post_object = null;
    private Error? post_err = null;

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

    public uint issue(uint event, void *user = null, Object? object = null, Error? err = null) {
        assert(event < descriptor.event_count);
        assert(state < descriptor.state_count);

        unowned Mapping? mapping = transitions[state, event];

        unowned Transition? transition = (mapping != null) ? mapping.transition : default_transition;
        if (transition == null) {
            string msg = "%s: No transition defined for %s@%s".printf(to_string(),
                descriptor.get_event_string(event), descriptor.get_state_string(state));

            if (this.abort_on_no_transition)
                error(msg);
            else
                critical(msg);

            return state;
        }

        // guard against reentrancy ... don't want to use a non-reentrant lock because then
        // the machine will simply hang; assertion is better to ferret out design flaws
        if (locked) {
            error("Fatal reentrancy on locked state machine %s: %s", descriptor.name,
                get_event_issued_string(state, event));
        }
        locked = true;

        uint old_state = state;
        state = transition(state, event, user, object, err);
        assert(state < descriptor.state_count);

        if (!locked) {
            error("Exited transition to unlocked state machine %s: %s", descriptor.name,
                get_transition_string(old_state, event, state));
        }
        locked = false;

        if (this.logging)
            message("%s: %s", to_string(), get_transition_string(old_state, event, state));

        // Perform post-transition if registered
        if (post_transition != null) {
            // clear post-transition before calling, in case this method is re-entered
            unowned PostTransition? perform = post_transition;
            void* perform_user = post_user;
            Object? perform_object = post_object;
            Error? perform_err = post_err;

            post_transition = null;
            post_user = null;
            post_object = null;
            post_err = null;

            perform(perform_user, perform_object, perform_err);
        }

        return state;
    }

    // Must be used carefully: this allows for a delegate (callback) to be called after the
    // *current* transition has occurred; thus, this method can *only* be called from within
    // a TransitionHandler.
    //
    // Note that if a second call to this method is made inside the same transition, the earlier
    // PostTransition is silently dropped.  Only one PostTransition call may be registered.
    //
    // Returns false if unable to register the PostTransition delegate for the reasons specified
    // above.
    public bool do_post_transition(PostTransition post_transition, void *user = null,
        Object? object = null, Error? err = null) {
        if (!locked) {
            warning("%s: Attempt to register post-transition while machine is unlocked", to_string());

            return false;
        }

        this.post_transition = post_transition;
        post_user = user;
        post_object = object;
        post_err = err;

        return true;
    }

    public string get_state_string(uint state) {
        return descriptor.get_state_string(state);
    }

    public string get_event_string(uint event) {
        return descriptor.get_event_string(event);
    }

    public string get_event_issued_string(uint state, uint event) {
        return "%s@%s".printf(descriptor.get_state_string(state), descriptor.get_event_string(event));
    }

    public string get_transition_string(uint old_state, uint event, uint new_state) {
        return "%s@%s -> %s".printf(descriptor.get_state_string(old_state), descriptor.get_event_string(event),
            descriptor.get_state_string(new_state));
    }

    public string to_string() {
        return "Machine %s [%s]".printf(descriptor.name, descriptor.get_state_string(state));
    }
}

