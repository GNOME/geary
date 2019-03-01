/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class Geary.Smtp.Response {
    public ResponseCode code { get; private set; }
    public ResponseLine first_line { get; private set; }
    public Gee.List<ResponseLine> lines { get; private set; }

    public Response(Gee.List<ResponseLine> lines) {
        assert(lines.size > 0);

        code = lines[0].code;
        first_line = lines[0];
        this.lines = lines.read_only_view;
    }

    [NoReturn]
    public void throw_error(string msg) throws SmtpError {
        throw new SmtpError.SERVER_ERROR("%s: %s", msg, first_line.to_string());
    }

    public string to_string() {
        StringBuilder builder = new StringBuilder();

        foreach (ResponseLine line in lines) {
            builder.append(line.to_string());
            builder.append("\n");
        }

        return builder.str;
    }
}

