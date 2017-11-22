/*
 * Copyright 2017 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A unit of work to be executed by {@link GenericAccount}.
 *
 * To queue an operation for execution, pass an instance to {@link
 * GenericAccount.queue_operation} when the account is opened. It will
 * added to the accounts queue and executed asynchronously when it
 * reaches the front.
 *
 * Execution of the operation is managed by {@link
 * AccountProcessor}. Since the processor will not en-queue duplicate
 * operations, implementations may override the {@link equal_to}
 * method to ensure that the same operation is not queued twice.
 */
public abstract class Geary.ImapEngine.AccountOperation : Geary.BaseObject {


    /**
     * Fired by after processing when the operation has completed.
     *
     * This is fired regardless of if an error was thrown after {@link
     * execute} is called. It is always fired after either {@link
     * succeeded} or {@link failed} is fired.
     *
     * Implementations should not fire this themselves, the
     * processor will do it for them.
     */
    public signal void completed();

    /**
     * Fired by the processor if the operation completes successfully.
     *
     * This is fired only after {@link execute} was called and did
     * not raise an error.
     *
     * Implementations should not fire this themselves, the
     * processor will do it for them.
     */
    public signal void succeeded();

    /**
     * Fired by the processor if the operation throws an error.
     *
     * This is fired only after {@link execute} was called and
     * threw an error. The argument is the error that was thrown.
     *
     * Implementations should not fire this themselves, the
     * processor will do it for them.
     */
    public signal void failed(Error err);


    /**
     * Called by the processor to execute this operation.
     */
    public abstract async void execute(Cancellable cancellable) throws Error;

    /**
     * Determines if this operation is equal to another.
     *
     * By default assumes that the same instance or two different
     * instances of the exact same type are equal. Implementations
     * should override it if they wish to guard against different
     * instances of the same high-level operation from being executed
     * twice.
     */
    public virtual bool equal_to(AccountOperation op) {
        return (op != null && (this == op || this.get_type() == op.get_type()));
    }

    /**
     * Provides a representation of this operation for debugging.
     *
     * By default simply returns the name of the class.
     */
    public virtual string to_string() {
        return this.get_type().name();
    }

}
