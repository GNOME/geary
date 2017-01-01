/* javascriptcore-4.0.vapi. */

[CCode (cprefix = "JS", gir_namespace = "JavaScriptCore", gir_version = "4.0", lower_case_cprefix = "JS_", cheader_filename = "JavaScriptCore/JavaScript.h")]
namespace JS {

	[CCode (cname = "JSContextRef")]
    [SimpleType]
	public struct Context {

        [CCode (cname = "JSValueIsBoolean")]
        public bool is_boolean(JS.Value value);

        [CCode (cname = "JSValueIsNumber")]
        public bool is_number(JS.Value value);

        [CCode (cname = "JSValueIsObject")]
        public bool is_object(JS.Value value);

        [CCode (cname = "JSValueToBoolean")]
        public bool to_boolean(JS.Value value);

        [CCode (cname = "JSValueToNumber")]
        public double to_number(JS.Value value, out JS.Value exception);

        [CCode (cname = "JSValueToObject")]
        public Object to_object(JS.Value value, out JS.Value exception);

        [CCode (cname = "JSValueToStringCopy")]
        public String to_string_copy(JS.Value value, out JS.Value exception);

        [CCode (cname = "JSEvaluateScript")]
        public Value evaluate_script(String script,
                                     Object? thisObject,
                                     String? sourceURL,
                                     int startingLineNumber,
                                     out Value? exception);

        [CCode (cname = "JSObjectMakeFunction")]
        public Object make_function(String? name,
                                    [CCode (array_length_pos=1.5)]
                                    String[]? parameterNames,
                                    String body,
                                    String? sourceURL,
                                    int startingLineNumber,
                                    out Value? exception);

        [CCode (cname = "JSObjectCallAsFunction")]
        public Value call_as_function(Object object,
                                      Object? thisObject,
                                      [CCode (array_length_pos=2.5)]
                                      Value[]? arguments,
                                      out Value? exception);

	}

	[CCode (cname = "JSGlobalContextRef")]
    [SimpleType]
	public struct GlobalContext : Context {

        [CCode (cname = "JSGlobalContextRelease")]
        public bool release();
	}

	[CCode (cname = "JSObjectRef")]
    [SimpleType]
	public struct Object {

        [CCode (cname = "JSObjectHasProperty", instance_pos = 1.1)]
        public bool has_property(Context ctx, String property_name);

        [CCode (cname = "JSObjectGetProperty", instance_pos = 1.1)]
        public String get_property(Context ctx,
                                   String property_name,
                                   out Value? exception);

	}

	[CCode (cname = "JSValueRef")]
    [SimpleType]
	public struct Value {

        [CCode (cname = "JSValueGetType", instance_pos = 1.1)]
        public JS.Type get_type(JS.Context context);

	}

	[CCode (cname = "JSStringRef", ref_function = "JSStringRetain", unref_function = "JSStringRelease")]
    [SimpleType]
	public struct String {

        [CCode (cname = "JSStringCreateWithUTF8CString")]
        public String.create_with_utf8_cstring(string str);

        [CCode (cname = "JSStringGetLength")]
        public int String.get_length();

        [CCode (cname = "JSStringGetMaximumUTF8CStringSize")]
        public int String.get_maximum_utf8_cstring_size();

        [CCode (cname = "JSStringGetUTF8CString")]
        public void String.get_utf8_cstring(string* buffer, int bufferSize);

        [CCode (cname = "JSStringRetain")]
        public void String.retain();

        [CCode (cname = "JSStringRelease")]
        public void String.release();

	}

	[CCode (cname = "JSType", has_type_id = false)]
	public enum Type {

        [CCode (cname = "kJSTypeUndefined")]
        UNDEFINED,

        [CCode (cname = "kJSTypeNull")]
        NULL,

        [CCode (cname = "kJSTypeBoolean")]
        BOOLEAN,

        [CCode (cname = "kJSTypeNumber")]
        NUMBER,

        [CCode (cname = "kJSTypeString")]
        STRING,

        [CCode (cname = "kJSTypeObject")]
        OBJECT
    }

}
