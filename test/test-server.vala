/*
 * Copyright 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * A simple mock server for testing network connections.
 *
 * To use it, unit tests should construct an instance as a fixture in
 * set up, specify a test script by adding lines and then check the
 * result, before stopping the server in tear down.
 */
public class TestServer : GLib.Object {


    /** Possible actions a script may take. */
    public enum Action {
        /**
         * The implicit first action.
         *
         * This does not need to be specified as a script action, it
         * will always be taken when a client connects.
         */
        CONNECTED,

        /** Send a line to the client. */
        SEND_LINE,

        /** Receive a line from the client. */
        RECEIVE_LINE,

        /** Wait for the client to disconnect. */
        WAIT_FOR_DISCONNECT,

        /** Disconnect immediately. */
        DISCONNECT;
    }


    /** A line of the server's script. */
    public struct Line {

        /** The action to take for this line. */
        public Action action;

        /**
         * The value for the action.
         *
         * If sending, this string will be sent. If receiving, the
         * expected line.
         */
        public string value;

    }

    /** The result of executing a script line. */
    public struct Result {

        /** The expected action. */
        public Line line;

        /** Was the expected action successful. */
        public bool succeeded;

        /** The actual string sent by a client when not as expected. */
        public string? actual;

        /** In case of an error being thrown, the error itself. */
        public GLib.Error? error;

    }


    private GLib.DataStreamNewlineType line_ending;
    private uint16 port;
    private GLib.ThreadedSocketService service =
        new GLib.ThreadedSocketService(10);
    private GLib.Cancellable running = new GLib.Cancellable();
    private Gee.List<Line?> script = new Gee.ArrayList<Line?>();
    private GLib.AsyncQueue<Result?> completion_queue =
        new GLib.AsyncQueue<Result?>();


    public TestServer(GLib.DataStreamNewlineType line_ending = CR_LF)
        throws GLib.Error {
        this.line_ending = line_ending;
        this.port = this.service.add_any_inet_port(null);
        this.service.run.connect((conn) => {
                handle_connection(conn);
                return true;
            });
        this.service.start();
    }

    public GLib.SocketConnectable get_client_address() {
        return new GLib.NetworkAddress("localhost", this.port);
    }

    public void add_script_line(Action action, string value) {
        this.script.add({ action, value });
    }

    public Result wait_for_script(GLib.MainContext loop) {
        Result? result = null;
        while (result == null) {
            loop.iteration(false);
            result = this.completion_queue.try_pop();
        }
        return result;
    }

    public void stop() {
        this.service.stop();
        this.running.cancel();
    }

    private void handle_connection(GLib.SocketConnection connection) {
        debug("Connected");
        var input = new GLib.DataInputStream(
            connection.input_stream
        );
        input.set_newline_type(this.line_ending);

        var output = new GLib.DataOutputStream(
            connection.output_stream
        );

        Line connected_line = { CONNECTED, "" };
        Result result = { connected_line, true, null, null };
        foreach (var line in this.script) {
            result.line = line;
            switch (line.action) {
            case CONNECTED:
                // no-op
                break;

            case SEND_LINE:
                debug("Sending: %s", line.value);
                try {
                    output.put_string(line.value);
                    switch (this.line_ending) {
                    case CR:
                        output.put_byte('\r');
                        break;
                    case LF:
                        output.put_byte('\n');
                        break;
                    default:
                        output.put_byte('\r');
                        output.put_byte('\n');
                        break;
                    }
                } catch (GLib.Error err) {
                    result.succeeded = false;
                    result.error = err;
                }
                break;

            case RECEIVE_LINE:
                debug("Waiting for: %s", line.value);
                try {
                    size_t len;
                    string? received = input.read_line(out len, this.running);
                    if (received == null || received != line.value) {
                        result.succeeded = false;
                        result.actual = received;
                    }
                } catch (GLib.Error err) {
                    result.succeeded = false;
                    result.error = err;
                }
                break;

            case WAIT_FOR_DISCONNECT:
                debug("Waiting for disconnect");
                var socket = connection.get_socket();
                try {
                    uint8 buffer[4096];
                    while (socket.receive_with_blocking(buffer, true) > 0) { }
                } catch (GLib.Error err) {
                    result.succeeded = false;
                    result.error = err;
                }
                break;

            case DISCONNECT:
                debug("Disconnecting");
                try {
                    connection.close(this.running);
                } catch (GLib.Error err) {
                    result.succeeded = false;
                    result.error = err;
                }
                break;
            }

            if (!result.succeeded) {
                break;
            }
        }
        if (result.succeeded) {
            debug("Done");
        } else if (result.error != null) {
            warning("Error: %s", result.error.message);
        } else if (result.line.action == RECEIVE_LINE) {
            warning("Received unexpected line: %s", result.actual ?? "(null)");
        } else {
            warning("Failed for unknown reason");
        }

        if (connection.is_connected()) {
            try {
                connection.close(this.running);
            } catch (GLib.Error err) {
                warning(
                    "Error closing test server connection: %s", err.message
                );
            }
        }

        this.completion_queue.push(result);
    }

}
