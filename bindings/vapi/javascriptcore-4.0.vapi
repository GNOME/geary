/*
 * Copyright 2017 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

[CCode (cprefix = "JS",
        gir_namespace = "JavaScriptCore",
        gir_version = "4.0",
        lower_case_cprefix = "JS_",
        cheader_filename = "JavaScriptCore/JavaScript.h")]
namespace JS {

	[CCode (cname = "JSContextRef")]
    [SimpleType]
	public struct Context {

        [CCode (cname = "JSEvaluateScript")]
        public Value evaluate_script(String script,
                                     Object? thisObject,
                                     String? sourceURL,
                                     int startingLineNumber,
                                     out Value? exception);

        [CCode (cname = "JSCheckScriptSyntax")]
        public Value check_script_syntax(String script,
                                         String? sourceURL,
                                         int startingLineNumber,
                                         out Value? exception);

	}

	[CCode (cname = "JSGlobalContextRef")]
    [SimpleType]
	public struct GlobalContext : Context {

        [CCode (cname = "JSGlobalContextRetain")]
        public bool retain();

        [CCode (cname = "JSGlobalContextRelease")]
        public bool release();

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

	[CCode (cname = "JSObjectRef")]
    [SimpleType]
	public struct Object {

        [CCode (cname = "JSObjectMakeFunction")]
        public Object.make_function(String? name,
                                    [CCode (array_length_pos=1.5)]
                                    String[]? parameterNames,
                                    String body,
                                    String? sourceURL,
                                    int startingLineNumber,
                                    out Value? exception);

        [CCode (cname = "JSObjectCallAsFunction", instance_pos = 1.1)]
        public Value call_as_function(Context ctx,
                                      Object? thisObject,
                                      [CCode (array_length_pos=2.5)]
                                      Value[]? arguments,
                                      out Value? exception);

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
        public Type get_type(Context context);

        [CCode (cname = "JSValueIsBoolean", instance_pos = 1.1)]
        public bool is_boolean(Context ctx);

        [CCode (cname = "JSValueIsNumber", instance_pos = 1.1)]
        public bool is_number(Context ctx);

        [CCode (cname = "JSValueIsObject", instance_pos = 1.1)]
        public bool is_object(Context ctx);

        [CCode (cname = "JSValueIsString", instance_pos = 1.1)]
        public bool is_string(Context ctx);

        [CCode (cname = "JSValueToBoolean", instance_pos = 1.1)]
        public bool to_boolean(Context ctx);

        [CCode (cname = "JSValueToNumber", instance_pos = 1.1)]
        public double to_number(Context ctx, out Value exception);

        [CCode (cname = "JSValueToObject", instance_pos = 1.1)]
        public Object to_object(Context ctx, out Value exception);

        [CCode (cname = "JSValueToStringCopy", instance_pos = 1.1)]
        public String to_string_copy(Context ctx, out Value exception);

	}

	[CCode (cname = "JSStringRef")]
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

}
