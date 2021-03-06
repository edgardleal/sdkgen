require "./target"
require "random/secure"

abstract class JavaTarget < Target
  def mangle(ident)
    if %w[
         boolean class if int byte do for while void float double long char synchronized
         instanceof extends implements interface abstract static public private protected
         final import package throw throws catch finally try new null else return continue
         break goto switch default case
         Object Class
       ].includes? ident
      "_" + ident
    else
      ident
    end
  end

  def native_type_not_primitive(t : AST::PrimitiveType)
    case t
    when AST::StringPrimitiveType  ; "String"
    when AST::IntPrimitiveType     ; "Integer"
    when AST::UIntPrimitiveType    ; "Integer"
    when AST::FloatPrimitiveType   ; "Double"
    when AST::DatePrimitiveType    ; "Calendar"
    when AST::DateTimePrimitiveType; "Calendar"
    when AST::BoolPrimitiveType    ; "Boolean"
    when AST::BytesPrimitiveType   ; "byte[]"
    when AST::VoidPrimitiveType    ; "void"
    else
      raise "BUG! Should handle primitive #{t.class}"
    end
  end

  def native_type_not_primitive(t : AST::Type)
    native_type(t)
  end

  def native_type(t : AST::PrimitiveType)
    case t
    when AST::StringPrimitiveType  ; "String"
    when AST::IntPrimitiveType     ; "int"
    when AST::UIntPrimitiveType    ; "int"
    when AST::FloatPrimitiveType   ; "double"
    when AST::DatePrimitiveType    ; "Calendar"
    when AST::DateTimePrimitiveType; "Calendar"
    when AST::BoolPrimitiveType    ; "boolean"
    when AST::BytesPrimitiveType   ; "byte[]"
    when AST::VoidPrimitiveType    ; "void"
    else
      raise "BUG! Should handle primitive #{t.class}"
    end
  end

  def native_type(t : AST::OptionalType)
    native_type_not_primitive(t.base)
  end

  def native_type(t : AST::ArrayType)
    "ArrayList<#{native_type_not_primitive(t.base)}>"
  end

  def native_type(t : AST::StructType | AST::EnumType)
    mangle t.name
  end

  def native_type(ref : AST::TypeReference)
    native_type ref.type
  end

  def generate_struct_type(t)
    String.build do |io|
      io << "public static class #{mangle t.name} implements Parcelable, Comparable<#{mangle t.name}> {\n"
      t.fields.each do |field|
        io << ident "public #{native_type field.type} #{mangle field.name};\n"
      end
      io << ident <<-END

public int compareTo(#{mangle t.name} other) {
    return toJSON().toString().compareTo(other.toJSON().toString());
}

public JSONObject toJSON() {
    try {
        return new JSONObject() {{

END
      t.fields.each do |field|
        io << ident ident ident ident "put(\"#{field.name}\", #{type_to_json field.type, mangle field.name});\n"
      end
      io << ident <<-END
        }};
    } catch (JSONException e) {
        e.printStackTrace();
        return new JSONObject();
    }
}

public static JSONArray toJSONArray(List<#{mangle t.name}> list) {
    JSONArray array = null;
    if (list != null && !list.isEmpty()) {
        array = new JSONArray();
        for (int i=0; i<list.size(); i++) {
            try{
                array.put(list.get(i).toJSON());
            } catch (Exception e) {
                e.printStackTrace();
            }
        }
    }
    return array;
}

public static #{mangle t.name} fromJSON(final JSONObject json) {
    return new #{mangle t.name}(json);
}

public static List<#{mangle t.name}> fromJSONArray(final JSONArray jsonArray) {
    ArrayList<#{mangle t.name}> list = null;
    if (jsonArray != null && jsonArray.length() > 0) {
        list = new ArrayList<#{mangle t.name}>();
        for (int i = 0; i < jsonArray.length(); i++) {
            try {
                JSONObject obj = jsonArray.getJSONObject(i);
                list.add(fromJSON(obj));
            } catch (Exception e) {
                e.printStackTrace();
            }
        }
    }
    return list;
}

public #{mangle t.name}() {
}

protected #{mangle t.name}(final JSONObject json) {
    try {

END
      t.fields.each do |field|
        io << ident ident ident "#{mangle field.name} = #{type_from_json field.type, "json", field.name.inspect};\n"
      end
      io << ident <<-END

    } catch (JSONException e) {
        e.printStackTrace();
    }
}

protected #{mangle t.name}(Parcel in) {
    try {
        final JSONObject json = new JSONObject(in.readString());

END
      t.fields.each do |field|
        io << ident ident ident "#{mangle field.name} = #{type_from_json field.type, "json", field.name.inspect};\n"
      end
      io << ident <<-END
    } catch (JSONException e) {
        e.printStackTrace();
    }
}

@Override
public void writeToParcel(Parcel dest, int flags) {
    dest.writeString(toJSON().toString());
}

@Override
public int describeContents() {
    return 0;
}

public static final Parcelable.Creator<#{mangle t.name}> CREATOR = new Parcelable.Creator<#{mangle t.name}>() {
    @Override
    public #{mangle t.name} createFromParcel(Parcel in) {
        return new #{mangle t.name}(in);
    }

    @Override
    public #{mangle t.name}[] newArray(int size) {
        return new #{mangle t.name}[size];
    }
};

END
      io << "}"
    end
  end

  def generate_enum_type(t)
    String.build do |io|
      io << "public enum #{mangle t.name} {\n"
      t.values.each do |value|
        io << ident "#{mangle value},\n"
      end
      io << "}"
    end
  end

  def type_from_json(t : AST::Type, obj : String, name : String)
    case t
    when AST::StringPrimitiveType
      "#{obj}.getString(#{name})"
    when AST::IntPrimitiveType, AST::UIntPrimitiveType
      "#{obj}.getInt(#{name})"
    when AST::FloatPrimitiveType
      "#{obj}.getDouble(#{name})"
    when AST::BoolPrimitiveType
      "#{obj}.getBoolean(#{name})"
    when AST::DatePrimitiveType
      "DateHelpers.decodeDate(#{obj}.getString(#{name}))"
    when AST::DateTimePrimitiveType
      "DateHelpers.decodeDateTime(#{obj}.getString(#{name}))"
    when AST::BytesPrimitiveType
      "Base64.decode(#{obj}.getString(#{name}), Base64.DEFAULT)"
    when AST::VoidPrimitiveType
      "null"
    when AST::OptionalType
      "#{obj}.isNull(#{name}) ? null : #{type_from_json(t.base, obj, name)}"
    when AST::ArrayType
      i = "i" + Random::Secure.hex[0, 5]
      ary = "ary" + Random::Secure.hex[0, 5]
      "new #{native_type t}() {{ final JSONArray #{ary} = #{obj}.getJSONArray(#{name}); for (int #{i} = 0; #{i} < #{ary}.length(); ++#{i}) {final int x#{i} = #{i}; add(#{type_from_json(t.base, "#{ary}", "x#{i}")});} }}"
    when AST::StructType
      "#{mangle t.name}.fromJSON(#{obj}.getJSONObject(#{name}))"
    when AST::EnumType
      "#{t.values.map { |v| "#{obj}.getString(#{name}).equals(#{v.inspect}) ? #{mangle t.name}.#{mangle v} : " }.join}null"
    when AST::TypeReference
      type_from_json(t.type, obj, name)
    else
      raise "Unknown type"
    end
  end

  def type_to_json(t : AST::Type, src : String)
    case t
    when AST::StringPrimitiveType, AST::IntPrimitiveType, AST::UIntPrimitiveType, AST::FloatPrimitiveType, AST::BoolPrimitiveType
      "#{src}"
    when AST::DatePrimitiveType
      "DateHelpers.encodeDate(#{src})"
    when AST::DateTimePrimitiveType
      "DateHelpers.encodeDateTime(#{src})"
    when AST::BytesPrimitiveType
      "Base64.encodeToString(#{src}, Base64.DEFAULT)"
    when AST::VoidPrimitiveType
      "JSONObject.NULL"
    when AST::OptionalType
      "#{src} == null ? JSONObject.NULL : #{type_to_json(t.base, src)}"
    when AST::ArrayType
      el = "el" + Random::Secure.hex[0, 5]
      "new JSONArray() {{ for (final #{native_type t.base} #{el} : #{src}) put(#{type_to_json t.base, "#{el}"}); }}"
    when AST::StructType
      "#{src}.toJSON()"
    when AST::EnumType
      "#{t.values.map { |v| "#{src} == #{mangle t.name}.#{mangle v} ? #{v.inspect} : " }.join}\"\""
    when AST::TypeReference
      type_to_json(t.type, src)
    else
      raise "Unknown type"
    end
  end
end
