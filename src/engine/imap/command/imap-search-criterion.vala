/* Copyright 2013 Yorba Foundation
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
    private Parameter parameter;
    
    /**
     * Create a single simple criterion for the {@link SearchCommand}.
     */
    public SearchCriterion(Parameter parameter) {
        this.parameter = parameter;
    }
    
    /**
     * Creates a simple search criterion.
     */
    public SearchCriterion.simple(string name) {
        parameter = prep_name(name);
    }
    
    /**
     * Create a single criterion with a simple name and custom value.
     */
    public SearchCriterion.parameter_value(string name, Parameter value) {
        parameter = make_list(prep_name(name), value);
    }
    
    /**
     * Create a single criterion with a simple name and custom value.
     *
     * @throws ImapError.INVALID if name must be transmitted as a {@link LiteralParameter}.
     */
    public SearchCriterion.string_value(string name, string value) {
        Parameter? valuep = StringParameter.get_best_for(value);
        if (valuep == null)
            valuep = new LiteralParameter(new Memory.StringBuffer(value));
        
        parameter = make_list(prep_name(name), valuep);
    }
    
    private static Parameter prep_name(string name) {
        Parameter? namep = StringParameter.get_best_for(name);
        if (namep == null) {
            warning("Using a search name that requires a literal parameter: %s", name);
            namep = new LiteralParameter(new Memory.StringBuffer(name));
        }
        
        return namep;
    }
    
    private static ListParameter make_list(Parameter namep, Parameter valuep) {
        ListParameter listp = new ListParameter();
        listp.add(namep);
        listp.add(valuep);
        
        return listp;
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
        ListParameter listp = new ListParameter();
        listp.add(StringParameter.get_best_for("or"));
        listp.add(a.to_parameter());
        listp.add(b.to_parameter());
        
        return new SearchCriterion(listp);
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
    public static SearchCriterion has_flag(MessageFlag flag) {
        string? keyword = flag.get_search_keyword(true);
        if (keyword != null)
            return new SearchCriterion.simple(keyword);
        
        return new SearchCriterion.parameter_value("keyword", flag.to_parameter());
    }
    
    /**
     * The IMAP SEARCH UNKEYWORD criterion, or if the {@link MessageFlag} has a macro, that value.
     */
    public static SearchCriterion has_not_flag(MessageFlag flag) {
        string? keyword = flag.get_search_keyword(false);
        if (keyword != null)
            return new SearchCriterion.simple(keyword);
        
        return new SearchCriterion.parameter_value("unkeyword", flag.to_parameter());
    }
    
    /**
     * The IMAP SEARCH ON criterion.
     */
    public static SearchCriterion on_internaldate(InternalDate internaldate) {
        return new SearchCriterion.parameter_value("on", internaldate.to_parameter());
    }
    
    /**
     * The IMAP SEARCH SINCE criterion.
     */
    public static SearchCriterion since_internaldate(InternalDate internaldate) {
        return new SearchCriterion.parameter_value("since", internaldate.to_parameter());
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
     * Returns the {@link SearchCriterion} as an IMAP {@link Parameter}.
     */
    public Parameter to_parameter() {
        return parameter;
    }
    
    public string to_string() {
        return parameter.to_string();
    }
}

