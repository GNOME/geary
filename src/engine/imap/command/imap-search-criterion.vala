/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A representation of a single IMAP SEARCH criteria.
 *
 * See [[http://tools.ietf.org/html/rfc3501#section-6.4.4]]
 *
 * The current implementation does not support searching by sent date or arbitrary header values.
 *
 * @see SearchCommand
 */

public class Geary.Imap.SearchCriterion : BaseObject {
    private Gee.List<Parameter> parameters = new Gee.ArrayList<Parameter>();

    /**
     * Create a single simple criterion for the {@link SearchCommand}.
     */
    public SearchCriterion(Parameter? parameter = null) {
        if (parameter != null)
            parameters.add(parameter);
    }

    /**
     * Creates a simple search criterion.
     */
    public SearchCriterion.simple(string name) {
        parameters.add(prep_name(name));
    }

    /**
     * Create a single criterion with a simple name and custom value.
     */
    public SearchCriterion.parameter_value(string name, Parameter value) {
        parameters.add(prep_name(name));
        parameters.add(value);
    }

    /**
     * Create a single criterion with a simple name and custom value.
     */
    public SearchCriterion.string_value(string name, string value) {
        parameters.add(prep_name(name));
        parameters.add(Parameter.get_for_string(value));
    }

    private static Parameter prep_name(string name) {
        Parameter? namep = StringParameter.try_get_best_for(name);
        if (namep == null) {
            warning("Using a search name that requires a literal parameter: %s", name);
            namep = new LiteralParameter(new Memory.StringBuffer(name));
        }

        return namep;
    }

    /**
     * The IMAP SEARCH ALL criterion.
     */
    public static SearchCriterion all() {
        return new SearchCriterion.simple("all");
    }

    /**
     * The IMAP SEARCH OR criterion, which operates on other {@link SearchCriterion}.
     */
    public static SearchCriterion or(SearchCriterion a, SearchCriterion b) {
        SearchCriterion criterion = new SearchCriterion.simple("or");

        // add each set of Parameters as lists (which are AND-ed)
        criterion.parameters.add(a.to_list_parameter());
        criterion.parameters.add(b.to_list_parameter());

        return criterion;
    }

    /**
     * The IMAP SEARCH NOT criterion.
     */
    public static SearchCriterion not(SearchCriterion a) {
        return new SearchCriterion.parameter_value("not", a.to_list_parameter());
    }

    /**
     * The IMAP SEARCH NEW criterion.
     */
    public static SearchCriterion new_messages() {
        return new SearchCriterion.simple("new");
    }

    /**
     * The IMAP SEARCH OLD criterion.
     */
    public static SearchCriterion old_messages() {
        return new SearchCriterion.simple("old");
    }

    /**
     * The IMAP SEARCH KEYWORD criterion, or if the {@link MessageFlag} has a macro, that value.
     */
    public static SearchCriterion has_flag(MessageFlag flag) throws ImapError {
        string? keyword = flag.get_search_keyword(true);
        if (keyword != null)
            return new SearchCriterion.simple(keyword);

        return new SearchCriterion.parameter_value("keyword", flag.to_parameter());
    }

    /**
     * The IMAP SEARCH UNKEYWORD criterion, or if the {@link MessageFlag} has a macro, that value.
     */
    public static SearchCriterion has_not_flag(MessageFlag flag) throws ImapError {
        string? keyword = flag.get_search_keyword(false);
        if (keyword != null)
            return new SearchCriterion.simple(keyword);

        return new SearchCriterion.parameter_value("unkeyword", flag.to_parameter());
    }

    /**
     * The IMAP SEARCH BEFORE criterion.
     */
    public static SearchCriterion before_internaldate(InternalDate internaldate) {
        return new SearchCriterion.parameter_value("before", internaldate.to_search_parameter());
    }

    /**
     * The IMAP SEARCH ON criterion.
     */
    public static SearchCriterion on_internaldate(InternalDate internaldate) {
        return new SearchCriterion.parameter_value("on", internaldate.to_search_parameter());
    }

    /**
     * The IMAP SEARCH SINCE criterion.
     */
    public static SearchCriterion since_internaldate(InternalDate internaldate) {
        return new SearchCriterion.parameter_value("since", internaldate.to_search_parameter());
    }

    /**
     * The IMAP SEARCH BODY criterion, which searches the body for the string.
     */
    public static SearchCriterion body(string value) {
        return new SearchCriterion.string_value("body", value);
    }

    /**
     * The IMAP SEARCH TEXT criterion, which searches the header and body for the string.
     */
    public static SearchCriterion text(string value) {
        return new SearchCriterion.string_value("text", value);
    }

    /**
     * The IMAP SEARCH SMALLER criterion.
     */
    public static SearchCriterion smaller(uint32 value) {
        return new SearchCriterion.parameter_value("smaller", new NumberParameter.uint32(value));
    }

    /**
     * The IMAP SEARCH LARGER criterion.
     */
    public static SearchCriterion larger(uint32 value) {
        return new SearchCriterion.parameter_value("larger", new NumberParameter.uint32(value));
    }

    /**
     * Specifies messages (by sequence number or UID) to limit the IMAP SEARCH to.
     */
    public static SearchCriterion message_set(MessageSet msg_set) {
        return msg_set.is_uid ? new SearchCriterion.parameter_value("uid", msg_set.to_parameter())
            : new SearchCriterion(msg_set.to_parameter());
    }

    /**
     * Returns the {@link SearchCriterion} as one or more IMAP {@link Parameter}s.
     *
     * Although each set of multiple parameters could be a list, the "usual" way of specifying
     * SEARCH arguments is without parentheses, and this strives to emulate that programmatically.
     *
     * The Parameters should be included in the {@link Command} in exactly the order returned.
     */
    public Gee.List<Parameter> to_parameters() {
        return parameters;
    }

    /**
     * Return {@link Parameter}s as a {@link ListParameter} if multiple, a single Parameter
     * otherwise.
     */
    public Parameter to_list_parameter() {
        if (parameters.size == 1)
            return parameters[0];

        ListParameter listp = new ListParameter();
        listp.add_all(parameters);

        return listp;
    }

    public string to_string() {
        return to_list_parameter().to_string();
    }
}

