/*
 * Copyright © 2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

public class MailMerge.TestReader : ValaUnit.TestCase {


    public TestReader() {
        base("MailMerge.TestReader");
        add_test("read_simple_lf", read_simple_lf);
        add_test("read_simple_crlf", read_simple_crlf);
        add_test("read_no_trailing_new_line", read_no_trailing_new_line);
        add_test("read_empty_records", read_empty_records);
        add_test("read_multi_byte_chars", read_multi_byte_chars);
        add_test("read_quoted", read_quoted);
    }

    public void read_simple_lf() throws GLib.Error {
        const string CSV = "foo,bar,baz\n1,2,3\n";

        new_reader.begin(CSV.data, this.async_completion);
        var reader = new_reader.end(async_result());

        reader.read_record.begin(this.async_completion);
        var headers = reader.read_record.end(async_result());
        assert_array(
            headers
        ).size(3).first_is("foo").at_index_is(1, "bar").at_index_is(2, "baz");

        reader.read_record.begin(this.async_completion);
        var data = reader.read_record.end(async_result());
        assert_array(
            data
        ).size(3).first_is("1").at_index_is(1, "2").at_index_is(2, "3");

        // Ensure both EOF and subsequent calls also return null

        reader.read_record.begin(this.async_completion);
        var eof1 = reader.read_record.end(async_result());
        assert_array_is_null(eof1);

        reader.read_record.begin(this.async_completion);
        var eof2 = reader.read_record.end(async_result());
        assert_array_is_null(eof2);
    }

    public void read_simple_crlf() throws GLib.Error {
        const string CSV = "foo,bar,baz\r\n1,2,3\r\n";

        new_reader.begin(CSV.data, this.async_completion);
        var reader = new_reader.end(async_result());

        reader.read_record.begin(this.async_completion);
        var headers = reader.read_record.end(async_result());
        assert_array(
            headers
        ).size(3).first_is("foo").at_index_is(1, "bar").at_index_is(2, "baz");

        reader.read_record.begin(this.async_completion);
        var data = reader.read_record.end(async_result());
        assert_array(
            data
        ).size(3).first_is("1").at_index_is(1, "2").at_index_is(2, "3");

        // Ensure both EOF and subsequent calls also return null

        reader.read_record.begin(this.async_completion);
        var eof1 = reader.read_record.end(async_result());
        assert_array_is_null(eof1);

        reader.read_record.begin(this.async_completion);
        var eof2 = reader.read_record.end(async_result());
        assert_array_is_null(eof2);
    }

    public void read_no_trailing_new_line() throws GLib.Error {
        const string CSV = "foo,bar,baz";

        new_reader.begin(CSV.data, this.async_completion);
        var reader = new_reader.end(async_result());

        reader.read_record.begin(this.async_completion);
        var headers = reader.read_record.end(async_result());
        assert_array(
            headers
        ).size(3).first_is("foo").at_index_is(1, "bar").at_index_is(2, "baz");

        reader.read_record.begin(this.async_completion);
        var eof1 = reader.read_record.end(async_result());
        assert_array_is_null(eof1);
    }

    public void read_empty_records() throws GLib.Error {
        const string CSV = ",,";

        new_reader.begin(CSV.data, this.async_completion);
        var reader = new_reader.end(async_result());

        reader.read_record.begin(this.async_completion);
        var headers = reader.read_record.end(async_result());
        assert_array(
            headers
        ).size(3).first_is("").at_index_is(1, "").at_index_is(2, "");

        reader.read_record.begin(this.async_completion);
        var eof1 = reader.read_record.end(async_result());
        assert_array_is_null(eof1);
    }

    public void read_multi_byte_chars() throws GLib.Error {
        const string CSV = "á,☃,🤘";

        new_reader.begin(CSV.data, this.async_completion);
        var reader = new_reader.end(async_result());

        reader.read_record.begin(this.async_completion);
        var headers = reader.read_record.end(async_result());
        assert_array(
            headers
        ).size(3).first_is("á").at_index_is(1, "☃").at_index_is(2, "🤘");

        reader.read_record.begin(this.async_completion);
        var eof1 = reader.read_record.end(async_result());
        assert_array_is_null(eof1);
    }

    public void read_quoted() throws GLib.Error {
        const string CSV = """"simple","foo""bar","foo,bar","foo
bar",""""""";

        new_reader.begin(CSV.data, this.async_completion);
        var reader = new_reader.end(async_result());

        reader.read_record.begin(this.async_completion);
        var headers = reader.read_record.end(async_result());
        assert_array(
            headers
        ).size(5)
        .first_is("simple")
        .at_index_is(1, "foo\"bar")
        .at_index_is(2, "foo,bar")
        .at_index_is(3, "foo\nbar")
        .at_index_is(4, "\"");

        reader.read_record.begin(this.async_completion);
        var eof1 = reader.read_record.end(async_result());
        assert_array_is_null(eof1);
    }

    private async MailMerge.Csv.Reader new_reader(uint8[] data)
        throws GLib.Error {
        return yield new MailMerge.Csv.Reader(
            new GLib.MemoryInputStream.from_data(data, null)
        );
    }

}
