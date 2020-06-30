/*
 * Copyright 2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

class Geary.RFC822.PartTest : TestCase {

    private const string CR_BODY = "This is an attachment.\n";
    private const string CRLF_BODY = "This is an attachment.\r\n";
    private const string ICAL_BODY = "BEGIN:VCALENDAR\r\nEND:VCALENDAR\r\n";
    private const string UTF8_BODY = "Тест.";


    public PartTest() {
        base("Geary.RFC822.PartTest");
        add_test("new_from_minimal_mime_part", new_from_minimal_mime_part);
        add_test("new_from_complete_mime_part", new_from_complete_mime_part);
        add_test("write_to_buffer_plain", write_to_buffer_plain);
        add_test("write_to_buffer_plain_crlf", write_to_buffer_plain_crlf);
        add_test("write_to_buffer_plain_ical", write_to_buffer_plain_ical);
        add_test("write_to_buffer_plain_utf8", write_to_buffer_plain_utf8);
    }

    public void new_from_minimal_mime_part() throws GLib.Error {
        Part test = new Part(new_part("test/plain", CR_BODY.data));

        assert_null(test.content_id, "content_id");
        assert_null(test.content_description, "content_description");
        assert_null(test.content_disposition, "content_disposition");
    }

    public void new_from_complete_mime_part() throws GLib.Error {
        const string TYPE = "text/plain";
        const string ID = "test-id";
        const string DESC = "test description";

        GMime.Part part = new_part(TYPE, CR_BODY.data);
        part.set_content_id(ID);
        part.set_content_description(DESC);
        part.set_content_disposition(
            GMime.ContentDisposition.parse(
                Geary.RFC822.get_parser_options(),
                "inline"
            )
        );

        Part test = new Part(part);

        assert_equal(test.content_type.to_string(), TYPE);
        assert_equal(test.content_id, ID);
        assert_equal(test.content_description, DESC);
        assert_non_null(test.content_disposition, "content_disposition");
        assert_equal<Geary.Mime.DispositionType?>(
            test.content_disposition.disposition_type, INLINE
        );
    }

    public void write_to_buffer_plain() throws GLib.Error {
        Part test = new Part(new_part("text/plain", CR_BODY.data));

        Memory.Buffer buf = test.write_to_buffer(Part.EncodingConversion.NONE);

        assert_equal(buf.to_string(), CR_BODY);
    }

    public void write_to_buffer_plain_crlf() throws GLib.Error {
        Part test = new Part(new_part("text/plain", CRLF_BODY.data));

        Memory.Buffer buf = test.write_to_buffer(Part.EncodingConversion.NONE);

        // CRLF should be stripped
        assert_equal(buf.to_string(), CR_BODY);
    }

    public void write_to_buffer_plain_ical() throws GLib.Error {
        Part test = new Part(new_part("text/calendar", ICAL_BODY.data));

        Memory.Buffer buf = test.write_to_buffer(Part.EncodingConversion.NONE);

        // CRLF should not be stripped
        assert_equal(buf.to_string(), ICAL_BODY);
    }

    public void write_to_buffer_plain_utf8() throws GLib.Error {
        Part test = new Part(new_part("text/plain", UTF8_BODY.data));

        Memory.Buffer buf = test.write_to_buffer(Part.EncodingConversion.NONE);

        assert_equal(buf.to_string(), UTF8_BODY);
    }

    private GMime.Part new_part(string? mime_type,
                                uint8[] body) {
        GMime.Part part = new GMime.Part.with_type("text", "plain");
        if (mime_type != null) {
            part.set_content_type(GMime.ContentType.parse(
                Geary.RFC822.get_parser_options(),
                mime_type
            ));
        }
        GMime.DataWrapper body_wrapper = new GMime.DataWrapper.with_stream(
            new GMime.StreamMem.with_buffer(body),
            GMime.ContentEncoding.BINARY
        );
        part.set_content(body_wrapper);
        part.encode(GMime.EncodingConstraint.7BIT);
        return part;
    }

}
