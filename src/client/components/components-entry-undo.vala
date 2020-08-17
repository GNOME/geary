/*
 * Copyright 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Provides per-GTK Entry undo and redo using a command stack.
 */
public class Components.EntryUndo : Geary.BaseObject {


    private const ActionEntry[] EDIT_ACTIONS = {
        { Action.Edit.UNDO, on_undo },
        { Action.Edit.REDO, on_redo },
    };


    private enum EditType { NONE, INSERT, DELETE; }


    private class EditCommand : Application.Command {


        private weak EntryUndo manager;
        private EditType edit;
        private int position;
        private string text;


        public EditCommand(EntryUndo manager,
                           EditType edit,
                           int position,
                           string text) {
            this.manager = manager;
            this.edit = edit;
            this.position = position;
            this.text = text;
        }

        public override async void execute(GLib.Cancellable? cancellable)
            throws GLib.Error {
            // No-op, has already been executed
        }

        public override async void undo(GLib.Cancellable? cancellable)
            throws GLib.Error {
            EntryUndo? manager = this.manager;
            if (manager != null) {
                manager.events_enabled = false;
                switch (this.edit) {
                case INSERT:
                    do_delete(manager.target);
                    break;
                case DELETE:
                    do_insert(manager.target);
                    break;
                case NONE:
                    // no-op
                    break;
                }
                manager.events_enabled = true;
            }
        }

        public override async void redo(GLib.Cancellable? cancellable)
            throws GLib.Error {
            EntryUndo? manager = this.manager;
            if (manager != null) {
                manager.events_enabled = false;
                switch (this.edit) {
                case INSERT:
                    do_insert(manager.target);
                    break;
                case DELETE:
                    do_delete(manager.target);
                    break;
                case NONE:
                    // no-op
                    break;
                }
                manager.events_enabled = true;
            }
        }

        private void do_insert(Gtk.Entry target) {
            int position = this.position;
            target.insert_text(this.text, -1, ref position);
            target.set_position(position);
        }

        private void do_delete(Gtk.Entry target) {
            target.delete_text(
                this.position, this.position + this.text.char_count()
            );
        }

    }


    /** The entry being managed */
    public Gtk.Entry target { get; private set; }

    private Application.CommandStack commands;
    private EditType last_edit = NONE;
    private int edit_start = 0;
    private int edit_end = 0;
    private GLib.StringBuilder edit_accumuluator = new GLib.StringBuilder();

    private bool events_enabled = true;

    private GLib.SimpleActionGroup edit_actions = new GLib.SimpleActionGroup();


    public EntryUndo(Gtk.Entry target) {
        this.edit_actions.add_action_entries(EDIT_ACTIONS, this);

        this.target = target;
        this.target.insert_action_group(Action.Edit.GROUP_NAME, this.edit_actions);
        this.target.insert_text.connect(on_inserted);
        this.target.delete_text.connect(on_deleted);

        this.commands = new Application.CommandStack();
        this.commands.executed.connect(this.update_command_actions);
        this.commands.undone.connect(this.update_command_actions);
        this.commands.redone.connect(this.update_command_actions);
    }

    ~EntryUndo() {
        this.target.insert_text.disconnect(on_inserted);
        this.target.delete_text.disconnect(on_deleted);
    }

    /** Resets the editing stack for the target entry. */
    public void reset() {
        this.last_edit = NONE;
        this.edit_accumuluator.truncate();
        this.commands.clear();
    }

    private void execute(Application.Command command) {
        bool complete = false;
        this.commands.execute.begin(
            command,
            null,
            (obj, res) => {
                try {
                    this.commands.execute.end(res);
                } catch (GLib.Error thrown) {
                    debug(
                        "Failed to execute entry edit command: %s",
                        thrown.message
                    );
                }
                complete = true;
            }
        );
        while (!complete) {
            Gtk.main_iteration();
        }
    }

    private void do_undo() {
        flush_command();
        bool complete = false;
        this.commands.undo.begin(
            null,
            (obj, res) => {
                try {
                    this.commands.undo.end(res);
                } catch (GLib.Error thrown) {
                    debug(
                        "Failed to undo entry edit command: %s",
                        thrown.message
                    );
                }
                complete = true;
            }
        );
        while (!complete) {
            Gtk.main_iteration();
        }
    }

    private void do_redo() {
        flush_command();
        bool complete = false;
        this.commands.redo.begin(
            null,
            (obj, res) => {
                try {
                    this.commands.redo.end(res);
                } catch (GLib.Error thrown) {
                    debug(
                        "Failed to redo entry edit command: %s",
                        thrown.message
                    );
                }
                complete = true;
            }
        );
        while (!complete) {
            Gtk.main_iteration();
        }
    }

    private void flush_command() {
        EditCommand? command = extract_command();
        if (command != null) {
            execute(command);
        }
    }

    private EditCommand? extract_command() {
        EditCommand? command = null;
        if (this.last_edit != NONE) {
            command = new EditCommand(
                this,
                this.last_edit,
                this.edit_start,
                this.edit_accumuluator.str
            );
            this.edit_accumuluator.truncate();
        }
        this.last_edit = NONE;
        return command;
    }

    private void update_command_actions() {
        ((GLib.SimpleAction) this.edit_actions.lookup_action(Action.Edit.UNDO))
            .set_enabled(this.commands.can_undo);
        ((GLib.SimpleAction) this.edit_actions.lookup_action(Action.Edit.REDO))
            .set_enabled(this.commands.can_redo);
    }

    private void on_inserted(string inserted, int inserted_len, ref int pos) {
        if (this.events_enabled) {
            // Normalise to something useful
            inserted_len = inserted.char_count();

            bool is_non_trivial = inserted_len > 1;
            bool insert_handled = false;
            if (this.last_edit == DELETE) {
                Application.Command? command = extract_command();
                if (command != null &&
                    this.edit_start == pos &&
                    is_non_trivial) {
                    // Delete followed by a non-trivial insert at the
                    // same position indicates something was probably
                    // pasted/spellchecked/completed/etc, so execute
                    // together as a single command.
                    this.last_edit = INSERT;
                    this.edit_start = pos;
                    this.edit_accumuluator.append(inserted);
                    command = new Application.CommandSequence({
                            command, extract_command()
                    });
                    insert_handled = true;
                }
                if (command != null) {
                    execute(command);
                }
            }

            if (!insert_handled) {
                bool is_disjoint_edit = (
                    this.last_edit == INSERT && this.edit_end != pos
                );
                bool is_non_alpha_num = (
                    inserted_len == 1 && !inserted.get_char(0).isalnum()
                );

                // Flush any existing edits if any of the special
                // cases hold
                if (is_disjoint_edit || is_non_alpha_num || is_non_trivial) {
                    flush_command();
                }

                if (this.last_edit == NONE) {
                    this.last_edit = INSERT;
                    this.edit_start = pos;
                    this.edit_end = pos;
                }

                this.edit_end += inserted_len;
                this.edit_accumuluator.append(inserted);

                // Flush the new edit if we don't want to coalesce
                // with subsequent inserts
                if (is_non_alpha_num || is_non_trivial) {
                    flush_command();
                }
            }
        }
    }

    private void on_deleted(int start, int end) {
        if (this.events_enabled) {
            // Normalise value of end to be something useful if needed
            string text = this.target.buffer.get_text();
            if (end < 0) {
                end = text.char_count();
            }

            // Don't flush non-trivial deletes since we want to be
            // able to combine them with non-trivial inserts for
            // better handling of pasting/spell-checking
            // replacement/etc.
            bool is_disjoint_edit = (
                this.last_edit == DELETE && this.edit_start != end
            );
            if (this.last_edit == INSERT || is_disjoint_edit) {
                flush_command();
            }

            if (this.last_edit == NONE) {
                this.last_edit = DELETE;
                this.edit_end = end;
            }

            this.edit_start = start;
            this.edit_accumuluator.prepend(
                text.slice(
                    text.index_of_nth_char(start),
                    text.index_of_nth_char(end)
                )
            );
        }
    }

    private void on_undo() {
        do_undo();
    }

    private void on_redo() {
        do_redo();
    }

}
