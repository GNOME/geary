/* Copyright 2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A convenience class to determine if a {@link ServerResponse} contains the result for a
 * particular {@link FetchBodyDataType}.
 */

public class Geary.Imap.FetchBodyDataIdentifier : BaseObject, Gee.Hashable<FetchBodyDataIdentifier> {
    private string original;
    private string munged;
    
    internal FetchBodyDataIdentifier(FetchBodyDataType body_data_type) {
        original = body_data_type.serialize_request();
        munged = munge(body_data_type.serialize_response());
    }
    
    internal FetchBodyDataIdentifier.from_parameter(StringParameter stringp) {
        original = stringp.value;
        munged = munge(original);
    }
    
    // prepare a version of the string modified to properly compare a version in a Command to the
    // matching result in a ServerResponse.
    //
    // Current changes:
    // * case-insensitive
    // * leading/trailing whitespace stripped
    // * BODY.peek[...] is returned as simply BODY[...] in some server implementations
    // * The span in the returned response is merely the offset ("1.15" becomes "1") because the
    //   associated literal specifies its length
    //
    // Some of these changes are reflected by using serialize_response() instead of
    // serialize_request() in the constructore.
    private static string munge(string str) {
        return str.down().strip();
    }
    
    public bool equal_to(FetchBodyDataIdentifier other) {
        return munged == other.munged;
    }
    
    public uint hash() {
        return str_hash(munged);
    }
    
    public string to_string() {
        return "%s/%s".printf(original, munged);
    }
}

