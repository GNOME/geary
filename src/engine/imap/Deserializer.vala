/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Imap.Deserializer {
    public enum Mode {
        LINE,
        BLOCK,
        FAILED
    }
    
    private enum State {
        TAG,
        START_PARAM,
        ATOM,
        QUOTED,
        QUOTED_ESCAPE,
        LITERAL,
        LITERAL_DATA_BEGIN,
        LITERAL_DATA,
        FAILED,
        COUNT
    }
    
    private static string state_to_string(uint state) {
        return ((State) state).to_string();
    }
    
    private enum Event {
        CHAR,
        EOL,
        DATA,
        COUNT
    }
    
    private static string event_to_string(uint event) {
        return ((Event) event).to_string();
    }
    
    // Atom specials includes space and close-parens, but those are handled in particular ways while
    // in the ATOM state, so they're not included here.  Also note that while documentation
    // indicates that the backslash cannot be used in an atom, they *are* used for message flags
    // and thus must be special-cased in the code.
    private static unichar[] atom_specials = {
        '(', '{', '%', '*', '\"'
    };
    
    // Tag specials are like atom specials but include the continuation character ('+').  Like atom
    // specials, the space is treated in a particular way, but unlike atom, the close-parens
    // character is not.  Also, the star character is allowed, although technically only correct
    // in the context of a status response; it's the responsibility of higher layers to catch this.
    private static unichar[] tag_specials = {
        '(', ')', '{', '%', '\"', '\\', '+'
    };
    
    private struct LiteralData {
        public unowned uint8[] data;
        
        public LiteralData(owned uint8[] data) {
            this.data = data;
        }
    }
    
    private static Geary.State.MachineDescriptor machine_desc = new Geary.State.MachineDescriptor(
        "Geary.Imap.Deserializer", State.TAG, State.COUNT, Event.COUNT,
        state_to_string, event_to_string);
    
    private Geary.State.Machine fsm;
    private ListParameter current;
    private RootParameters root = new RootParameters();
    private StringBuilder? current_string = null;
    private LiteralParameter? current_literal = null;
    private long literal_length_remaining = 0;
    
    public signal void parameters_ready(RootParameters root);
    
    public signal void failed();
    
    public Deserializer() {
        current = root;
        
        Geary.State.Mapping[] mappings = {
            new Geary.State.Mapping(State.TAG, Event.CHAR, on_tag_or_atom_char),
            
            new Geary.State.Mapping(State.START_PARAM, Event.CHAR, on_first_param_char),
            new Geary.State.Mapping(State.START_PARAM, Event.EOL, on_eol),
            
            new Geary.State.Mapping(State.ATOM, Event.CHAR, on_tag_or_atom_char),
            new Geary.State.Mapping(State.ATOM, Event.EOL, on_atom_eol),
            
            new Geary.State.Mapping(State.QUOTED, Event.CHAR, on_quoted_char),
            
            new Geary.State.Mapping(State.QUOTED_ESCAPE, Event.CHAR, on_quoted_escape_char),
            
            new Geary.State.Mapping(State.LITERAL, Event.CHAR, on_literal_char),
            
            new Geary.State.Mapping(State.LITERAL_DATA_BEGIN, Event.EOL, on_literal_data_begin_eol),
            
            new Geary.State.Mapping(State.LITERAL_DATA, Event.DATA, on_literal_data)
        };
        
        fsm = new Geary.State.Machine(machine_desc, mappings, on_bad_transition);
    }
    
    // Push a line (without the CRLF!).
    public Mode push_line(string line) {
        assert(get_mode() == Mode.LINE);
        
        int index = 0;
        unichar ch;
        while (line.get_next_char(ref index, out ch)) {
            if (fsm.issue(Event.CHAR, &ch) == State.FAILED) {
                failed();
                
                return Mode.FAILED;
            }
        }
        
        if (fsm.issue(Event.EOL) == State.FAILED) {
            failed();
            
            return Mode.FAILED;
        }
        
        return get_mode();
    }
    
    public long get_max_data_length() {
        return literal_length_remaining;
    }
    
    // Push a block of literal data
    public Mode push_data(uint8[] data) {
        assert(get_mode() == Mode.BLOCK);
        
        LiteralData literal_data = LiteralData(data);
        if (fsm.issue(Event.DATA, &literal_data) == State.FAILED) {
            failed();
            
            return Mode.FAILED;
        }
        
        return get_mode();
    }
    
    public Mode get_mode() {
        switch (fsm.get_state()) {
            case State.LITERAL_DATA:
                return Mode.LINE;
            
            case State.FAILED:
                return Mode.FAILED;
            
            default:
                return Mode.LINE;
        }
    }
    
    private bool is_current_string_empty() {
        return (current_string == null) || is_empty_string(current_string.str);
    }
    
    private void append_to_string(unichar ch) {
        if (current_string == null)
            current_string = new StringBuilder();
        
        current_string.append_unichar(ch);
    }
    
    private void append_to_literal(uint8[] data) {
        if (current_literal == null)
            current_literal = new LiteralParameter(data);
        else
            current_literal.add(data);
    }
    
    private void save_string_parameter() {
        if (is_current_string_empty())
            return;
        
        save_parameter(new StringParameter(current_string.str));
        current_string = null;
    }
    
    private void save_literal_parameter() {
        if (current_literal == null)
            return;
        
        save_parameter(current_literal);
        current_literal = null;
    }
    
    private void save_parameter(Parameter param) {
        current.add(param);
    }
    
    private void push() {
        ListParameter child = new ListParameter(current);
        current.add(child);
        
        current = child;
    }
    
    private State pop() {
        ListParameter? parent = current.get_parent();
        if (parent == null) {
            warning("Attempt to close unopened list");
            
            return State.FAILED;
        }
        
        current = parent;
        
        return State.START_PARAM;
    }
    
    private State flush_params() {
        if (current != root) {
            warning("Unclosed list in parameters");
            
            return State.FAILED;
        }
        
        if (!is_current_string_empty() || current_literal != null || literal_length_remaining > 0) {
            warning("Unfinished parameter");
            
            return State.FAILED;
        }
        
        parameters_ready(root);
        
        root = new RootParameters();
        current = root;
        
        return State.TAG;
    }
    
    //
    // Transition handlers
    //
    
    private uint on_first_param_char(uint state, uint event, void *user) {
        // look for opening characters to special parameter formats, otherwise jump to atom
        // handler (i.e. don't drop this character in the case of atoms)
        switch (*((unichar *) user)) {
            case '{':
                return State.LITERAL;
            
            case '\"':
                return State.QUOTED;
            
            case '(':
                // open list
                push();
                
                return State.START_PARAM;
            
            case ')':
                // close list
                return pop();
            
            default:
                return on_tag_or_atom_char(State.ATOM, event, user);
        }
    }
    
    private uint on_eol(uint state, uint event, void *user) {
        return flush_params();
    }
    
    private uint on_tag_or_atom_char(uint state, uint event, void *user) {
        assert(state == State.TAG || state == State.ATOM);
        
        unichar ch = *((unichar *) user);
        
        // drop everything above 0x7F
        if (ch > 0x7F)
            return state;
        
        // drop control characters
        if (ch.iscntrl())
            return state;
        
        // tags and atoms have different special characters
        if (state == State.TAG && (ch in tag_specials))
            return state;
        else if (state == State.ATOM && (ch in atom_specials))
            return state;
        
        // message flag indicator is only legal at start of atom
        if (state == State.ATOM && ch == '\\' && !is_current_string_empty())
            return state;
        
        // space indicates end-of-atom or end-of-tag
        if (ch == ' ') {
            save_string_parameter();
            
            return State.START_PARAM;
        }
        
        // close-parens after an atom indicates end-of-list
        if (state == State.ATOM && ch == ')') {
            save_string_parameter();
            
            return pop();
        }
        
        append_to_string(ch);
        
        return state;
    }
    
    private uint on_atom_eol(uint state, uint event, void *user) {
        // clean up final atom
        save_string_parameter();
        
        return flush_params();
    }
    
    private uint on_quoted_char(uint state, uint event, void *user) {
        unichar ch = *((unichar *) user);
        
        // drop anything above 0x7F
        if (ch > 0x7F)
            return State.QUOTED;
        
        // drop NUL, CR, and LF
        if (ch == '\0' || ch == '\r' || ch == '\n')
            return State.QUOTED;
        
        // look for escaped characters
        if (ch == '\\')
            return State.QUOTED_ESCAPE;
        
        // DQUOTE ends quoted string and return to parsing atoms
        if (ch == '\"') {
            save_string_parameter();
            
            return State.START_PARAM;
        }
        
        append_to_string(ch);
        
        return State.QUOTED;
    }
    
    private uint on_quoted_escape_char(uint state, uint event, void *user) {
        unichar ch = *((unichar *) user);
        
        // only two accepted escaped characters: double-quote and backslash
        // everything else dropped on the floor
        switch (ch) {
            case '\"':
            case '\\':
                append_to_string(ch);
            break;
        }
        
        return State.QUOTED;
    }
    
    private uint on_literal_char(uint state, uint event, void *user) {
        unichar ch = *((unichar *) user);
        
        // if close-bracket, end of literal length field -- next event must be EOL
        if (ch == '}') {
            // empty literal treated as garbage
            if (is_current_string_empty())
                return State.FAILED;
            
            literal_length_remaining = long.parse(current_string.str);
            if (literal_length_remaining < 0) {
                warning("Negative literal data length %ld", literal_length_remaining);
                
                return State.FAILED;
            }
            
            return State.LITERAL_DATA_BEGIN;
        }
        
        // drop anything non-numeric
        if (!ch.isdigit())
            return State.LITERAL;
        
        append_to_string(ch);
        
        return State.LITERAL;
    }
    
    private uint on_literal_data_begin_eol(uint state, uint event, void *user) {
        return State.LITERAL_DATA;
    }
    
    private uint on_literal_data(uint state, uint event, void *user) {
        LiteralData *literal_data = (LiteralData *) user;
        
        assert(literal_data.data.length <= literal_length_remaining);
        literal_length_remaining -= literal_data.data.length;
        
        append_to_literal(literal_data.data);
        if (literal_length_remaining > 0)
            return State.LITERAL_DATA;
            
        save_literal_parameter();
        
        return State.START_PARAM;
    }
    
    private uint on_bad_transition(uint state, uint event, void *user) {
        warning("Bad event %s at state %s", event_to_string(event), state_to_string(state));
        
        return State.FAILED;
    }
}

