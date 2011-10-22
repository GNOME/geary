/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

/**
 * A utility class for building async-based command-line programs.  Users should subclass MainAsync
 * and provide an exec_async() method.  It can return an int as the program's exit code.  It can
 * also throw an exception which is caught by MainAsync and printed to stderr.
 *
 * Then, in main(), create the subclasses object and call its exec() method, returning its int
 * from main as the program's exit code.  (If exec_async() throws an exception, main will return
 * EXCEPTION_EXIT_CODE, which is 255.)  Thus, main() should look something like this:
 *
 * int main(string[] args) {
 *     return new MyMainAsync(args).exec();
 * }
 */
public abstract class MainAsync : Object {
    public const int EXCEPTION_EXIT_CODE = 255;
    
    public string[] args;
    
    private MainLoop main_loop = new MainLoop();
    private int ec = 0;
    
    public MainAsync(string[] args) {
        this.args = args;
    }
    
    public int exec() {
        exec_async.begin(on_exec_completed);
        
        main_loop.run();
        
        return ec;
    }
    
    private void on_exec_completed(Object? source, AsyncResult result) {
        try {
            ec = exec_async.end(result);
        } catch (Error err) {
            stderr.printf("%s\n", err.message);
            ec = EXCEPTION_EXIT_CODE;
        }
        
        main_loop.quit();
    }
    
    protected abstract async int exec_async() throws Error;
}

