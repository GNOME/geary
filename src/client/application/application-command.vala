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
     * Determines if a command can be undone.
     *
     * When passed to {@link CommandStack}, the stack will check this
     * property after the command has been executed, and if false the
     * non-undo-able command will not be put on the undo stack.
     *
     * Returns true by default, derived classes may override if their
     * {@link undo} method should not be called.
     */
    public virtual bool can_undo {
        get { return true; }
    }

    /**
     * Determines if a command can be redone.
     *
     * After this command has been undone by the stack, it will check
     * this property and if false the non-redo-able command will not
     * be put on the redo stack.
     *
     * Returns true by default, derived classes may override if their
     * {@link undo} method should not be called.
     */
    public virtual bool can_redo {
        get { return true; }
    }

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
     * True if executed_label should be displayed only briefly to the user.
     * Set this to true for very frequent notifications.
     */
    public bool executed_notification_brief {
        get; protected set; default = false;
    }

    /**
     * A human-readable label describing the result of calling {@link undo}.
     *
     * This can be used in a user interface to indicate the effects of
     * the action just executed. For example, "Conversation restored
     * from Trash".
     */
    public string? undone_label { get; protected set; default = null; }


    /**
     * Emitted when the command was successfully executed.
     *
     * Command implementations must not manage this signal, it will be
     * emitted by {@link CommandStack} as needed.
     */
    public virtual signal void executed() {
        // no-op
    }

    /**
     * Emitted when the command was successfully undone.
     *
     * Command implementations must not manage this signal, it will be
     * emitted by {@link CommandStack} as needed.
     */
    public virtual signal void undone() {
        // no-op
    }

    /**
     * Emitted when the command was successfully redone.
     *
     * Command implementations must not manage this signal, it will be
     * emitted by {@link CommandStack} as needed.
     */
    public virtual signal void redone() {
        // no-op
    }


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

    /** Determines if this command is equal to another. */
    public virtual bool equal_to(Command other) {
        return (this == other);
    }

    /** Returns a string representation of the command for debugging. */
    public virtual string to_string() {
        return get_type().name();
    }

}


/**
 * A command that executes a sequence of other commands.
 *
 * When initially executed or redone, commands will be processed
 * individually in the given order. When undone, commands will be
 * processed individually in reverse order.
 */
public class Application.CommandSequence : Command {


    /**
     * Emitted when the command was successfully executed.
     *
     * Ensures the same signal is emitted on all commands in the
     * sequence, in order.
     */
    public override void executed() {
       foreach (Command command in this.commands) {
           command.executed();
       }
    }

    /**
     * Emitted when the command was successfully undone.
     *
     * Ensures the same signal is emitted on all commands in the
     * sequence, in reverse order.
     */
    public override void undone() {
       foreach (Command command in reversed_commands()) {
           command.undone();
       }
    }

    /**
     * Emitted when the command was successfully redone.
     *
     * Ensures the same signal is emitted on all commands in the
     * sequence, in order.
     */
    public override void redone() {
       foreach (Command command in this.commands) {
           command.redone();
       }
    }


    private Gee.List<Command> commands = new Gee.LinkedList<Command>();


    public CommandSequence(Command[]? commands = null) {
        if (commands != null) {
            this.commands.add_all_array(commands);
        }
    }


    /**
     * Executes all commands in the sequence, sequentially.
     */
    public override async void execute(GLib.Cancellable? cancellable)
       throws GLib.Error {
       foreach (Command command in this.commands) {
           yield command.execute(cancellable);
       }
    }

    /**
     * Un-does all commands in the sequence, in reverse order.
     */
    public override async void undo(GLib.Cancellable? cancellable)
       throws GLib.Error {
       foreach (Command command in reversed_commands()) {
           yield command.undo(cancellable);
       }
    }

    /**
     * Re-does all commands in the sequence, sequentially.
     */
    public override async void redo(GLib.Cancellable? cancellable)
       throws GLib.Error {
       foreach (Command command in this.commands) {
           yield command.redo(cancellable);
       }
    }

    private Gee.List<Command> reversed_commands() {
       var reversed = new Gee.LinkedList<Command>();
       foreach (Command command in this.commands) {
           reversed.insert(0, command);
       }
       return reversed;
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

        if (undo_label != null) {
            this.undo_label = undo_label.printf(this.old_value);
        }
        if (redo_label != null) {
            this.redo_label = redo_label.printf(this.new_value);
        }
        if (executed_label != null) {
            this.executed_label = executed_label.printf(this.new_value);
        }
        if (undone_label != null) {
            this.undone_label = undone_label.printf(this.old_value);
        }
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


    /** Stack of commands that can be undone. */
    protected Gee.Deque<Command> undo_stack = new Gee.LinkedList<Command>();

    /** Stack of commands that can be redone. */
    protected Gee.Deque<Command> redo_stack = new Gee.LinkedList<Command>();


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
    public virtual async void execute(Command target, GLib.Cancellable? cancellable)
        throws GLib.Error {
        debug("Executing: %s", target.to_string());
        yield target.execute(cancellable);

        update_undo_stack(target);
        this.can_undo = !this.undo_stack.is_empty;

        this.redo_stack.clear();
        this.can_redo = false;

        executed(target);
        target.executed();
    }

    /**
     * Pops a command off the undo stack and un-does is.
     *
     * This calls {@link Command.undo} on the topmost command on the
     * undo stack and if no error is thrown, pushes it on the redo
     * stack. If an error is thrown, the command is discarded and the
     * redo stack is emptied.
     */
    public virtual async void undo(GLib.Cancellable? cancellable)
        throws GLib.Error {
        if (!this.undo_stack.is_empty) {
            Command target = this.undo_stack.poll_head();

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

            update_redo_stack(target);
            this.can_redo = !this.redo_stack.is_empty;

            undone(target);
            target.undone();
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
    public virtual async void redo(GLib.Cancellable? cancellable)
        throws GLib.Error {
        if (!this.redo_stack.is_empty) {
            Command target = this.redo_stack.poll_head();

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

            update_undo_stack(target);
            this.can_undo = !this.undo_stack.is_empty;

            redone(target);
            target.redone();
        }
    }

    /** Returns the command at the top of the undo stack, if any. */
    public Command? peek_undo() {
        return this.undo_stack.is_empty ? null : this.undo_stack.peek_head();
    }

    /** Returns the command at the top of the redo stack, if any. */
    public Command? peek_redo() {
        return this.redo_stack.is_empty ? null : this.redo_stack.peek_head();
    }

    /** Clears all commands from both the undo and redo stacks. */
    public void clear() {
        this.undo_stack.clear();
        this.can_undo = false;
        this.redo_stack.clear();
        this.can_redo = false;
    }

    /**
     * Updates the undo stack when a command is executed or re-done.
     *
     * By default, this pushes the command to the head of the undo
     * stack if {@link Command.can_undo} is true.
     */
    protected virtual void update_undo_stack(Command target) {
        if (target.can_undo) {
            this.undo_stack.offer_head(target);
        }
    }

    /**
     * Updates the redo stack when a command is undone.
     *
     * By default, this pushes the command to the head of the redo
     * stack if {@link Command.can_undo} is true.
     */
    protected virtual void update_redo_stack(Command target) {
        if (target.can_redo) {
            this.redo_stack.offer_head(target);
        }
    }

}
