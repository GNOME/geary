/*
 * Copyright 2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */


/**
 * A generic application user command with undo and redo support.
 */
public abstract class Application.Command : GLib.Object {


    /**
     * A human-readable label describing the effect of calling {@link undo}.
     *
     * This can be used in a user interface, perhaps as a tooltip for
     * an Undo button, to indicate what will happen if the command is
     * un-done. For example, "Conversation restored from Trash".
     */
    public string? undo_label { get; protected set; default = null; }

    /**
     * A human-readable label describing the effect of calling {@link redo}.
     *
     * This can be used in a user interface, perhaps as a tooltip for
     * a Redo button, to indicate what will happen if the command is
     * re-done. For example, "Conversation restored from Trash".
     */
    public string? redo_label { get; protected set; default = null; }

    /**
     * A human-readable label describing the result of calling {@link execute}.
     *
     * This can be used in a user interface to indicate the effects of
     * the action just executed. For example, "Conversation moved to
     * Trash".
     *
     * Since the effects of re-doing a command should be identical to
     * that of executing it, this string can also be used to describe
     * the effects of {@link redo}.
     */
    public string? executed_label { get; protected set; default = null; }

    /**
     * A human-readable label describing the result of calling {@link undo}.
     *
     * This can be used in a user interface to indicate the effects of
     * the action just executed. For example, "Conversation restored
     * from Trash".
     */
    public string? undone_label { get; protected set; default = null; }


    /**
     * Called by {@link CommandStack} to execute the command.
     *
     * Applications should not call this method directly, rather pass
     * it to {@link CommandStack.execute}.
     *
     * Command implementations should apply the user command when this
     * method is called. It will be called at most once when used sole
     * with the command stack.
     */
    public abstract async void execute(GLib.Cancellable? cancellable)
        throws GLib.Error;

    /**
     * Called by {@link CommandStack} to undo the executed command.
     *
     * Applications should not call this method directly, rather they
     * should call {@link CommandStack.undo} so that it is managed
     * correctly.
     *
     * Command implementations should reverse the user command carried
     * out by the call to {@link execute}. It will be called zero or
     * more times, but only ever after a call to either {@link
     * execute} or {@link redo} when used sole with the command stack.
     */
    public abstract async void undo(GLib.Cancellable? cancellable)
        throws GLib.Error;
        
    /**
     * Called by {@link CommandStack} to redo the executed command.
     *
     * Applications should not call this method directly, rather they
     * should call {@link CommandStack.redo} so that it is managed
     * correctly.
     *
     * Command implementations should re-apply a user command that has
     * been un-done by a call to {@link undo}. By default, this method
     * simply calls {@link execute}, but implementations with more
     * complex requirements can override this. It will called zero or
     * more times, but only ever after a call to {@link undo} when
     * used sole with the command stack.
     */
    public virtual async void redo(GLib.Cancellable? cancellable)
        throws GLib.Error {
        yield execute(cancellable);
    }

    /** Returns a string representation of the command for debugging. */
    public virtual string to_string() {
        return get_type().name();
    }

}


/**
 * A command that updates a GObject instance property.
 *
 * This command will save the existing property value on execution
 * before updating it with the new given property, restore it on undo,
 * and re-execute on redo. The type parameter T must be the same type
 * as the property being updated and must be nullable if the property
 * is nullable.
 */
public class Application.PropertyCommand<T> : Application.Command {


    private GLib.Object object;
    private string property_name;
    private T new_value;
    private T old_value;


    public PropertyCommand(GLib.Object object,
                           string property_name,
                           T new_value,
                           string? undo_label = null,
                           string? redo_label = null,
                           string? executed_label = null,
                           string? undone_label = null) {
        this.object = object;
        this.property_name = property_name;
        this.new_value = new_value;

        this.object.get(this.property_name, ref this.old_value);

        this.undo_label = undo_label.printf(this.old_value);
        this.redo_label = redo_label.printf(this.new_value);
        this.executed_label = executed_label.printf(this.new_value);
        this.undone_label = undone_label.printf(this.old_value);
    }

    public async override void execute(GLib.Cancellable? cancellable) {
        this.object.set(this.property_name, this.new_value);
    }

    public async override void undo(GLib.Cancellable? cancellable) {
        this.object.set(this.property_name, this.old_value);
    }

    public override string to_string() {
        return "%s(%s)".printf(base.to_string(), this.property_name);
    }

}


/**
 * A stack of executed application commands.
 *
 * The command stack manages calling the {@link Command.execute},
 * {@link Command.undo}, and {@link Command.redo} methods on an
 * application's user commands. It enforces the strict ordering of
 * calls to those methods so that if a command is well implemented,
 * then the application will be in the same state after executing and
 * re-doing a command, and the application will return to the original
 * state after being undone, both for individual commands and between
 * after a number of commands have been executed.
 *
 * Applications should call {@link execute} to execute a command,
 * which will push it on to an undo stack after executing it. The
 * command at the top of the stack can be undone by calling {@link
 * undo}, which undoes the command, pops it from the undo stack and
 * pushes it on the redo stack. If a new command is executed when the
 * redo stack is non-empty, it will be emptied first.
 */
public class Application.CommandStack : GLib.Object {


    // The can_undo and can_redo are automatic properties so
    // applications can get notified when they change.

    /** Determines if there are any commands able to be un-done. */
    public bool can_undo { get; private set; }

    /** Determines if there are any commands available to be re-done. */
    public bool can_redo { get; private set; }


    private Gee.LinkedList<Command> undo_stack = new Gee.LinkedList<Command>();
    private Gee.LinkedList<Command> redo_stack = new Gee.LinkedList<Command>();


    /** Fired when a command is first executed */
    public signal void executed(Command command);

    /** Fired when a command is un-done */
    public signal void undone(Command command);

    /** Fired when a command is re-executed */
    public signal void redone(Command command);


    /**
     * Executes an command and pushes it onto the undo stack.
     *
     * This calls {@link Command.execute} and if no error is thrown,
     * pushes the command onto the undo stack.
     */
    public async void execute(Command target, GLib.Cancellable? cancellable)
        throws GLib.Error {
        debug("Executing: %s", target.to_string());
        yield target.execute(cancellable);

        this.undo_stack.insert(0, target);
        this.can_undo = true;

        this.redo_stack.clear();
        this.can_redo = false;

        executed(target);
    }

    /**
     * Pops a command off the undo stack and un-does is.
     *
     * This calls {@link Command.undo} on the topmost command on the
     * undo stack and if no error is thrown, pushes it on the redo
     * stack. If an error is thrown, the command is discarded and the
     * redo stack is emptied.
     */
    public async void undo(GLib.Cancellable? cancellable)
        throws GLib.Error {
        if (!this.undo_stack.is_empty) {
            Command target = this.undo_stack.remove_at(0);

            if (this.undo_stack.is_empty) {
                this.can_undo = false;
            }

            debug("Undoing: %s", target.to_string());
            try {
                yield target.undo(cancellable);
            } catch (Error err) {
                this.redo_stack.clear();
                this.can_redo = false;
                throw err;
            }

            this.redo_stack.insert(0, target);
            this.can_redo = true;
            undone(target);
        }
    }

    /**
     * Pops a command off the redo stack and re-applies it.
     *
     * This calls {@link Command.redo} on the topmost command on the
     * redo stack and if no error is thrown, pushes it on the undo
     * stack. If an error is thrown, the command is discarded and the
     * redo stack is emptied.
     */
    public async void redo(GLib.Cancellable? cancellable)
        throws GLib.Error {
        if (!this.redo_stack.is_empty) {
            Command target = this.redo_stack.remove_at(0);

            if (this.redo_stack.is_empty) {
                this.can_redo = false;
            }

            debug("Redoing: %s", target.to_string());
            try {
                yield target.redo(cancellable);
            } catch (Error err) {
                this.redo_stack.clear();
                this.can_redo = false;
                throw err;
            }

            this.undo_stack.insert(0, target);
            this.can_undo = true;
            redone(target);
        }
    }

    /** Returns the command at the top of the undo stack, if any. */
    public Command? peek_undo() {
        return this.undo_stack.is_empty ? null : this.undo_stack[0];
    }

    /** Returns the command at the top of the redo stack, if any. */
    public Command? peek_redo() {
        return this.redo_stack.is_empty ? null : this.redo_stack[0];
    }

    /** Clears all commands from both the undo and redo stacks. */
    public void clear() {
        this.undo_stack.clear();
        this.can_undo = false;
        this.redo_stack.clear();
        this.can_redo = false;
    }

}
