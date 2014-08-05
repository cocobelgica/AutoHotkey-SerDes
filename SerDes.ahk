/* Function:     SerDes
 *     Serializes an AHK object to string and optionally dumps it into a file.
 *     Deserializes a 'SerDes()' formatted string to an AHK object.
 * AHK Version:  Tested on v1.1.15.03 and v2.0-a049
 *
 * Syntax (Serialize):
 *     str   := SerDes( obj )
 *     bytes := SerDes( obj [, outfile ] )
 * Parameter(s):
 *     str       [retval]   - String representation of the object.
 *     bytes     [retval]   - Bytes written to 'outfile'.
 *     obj       [in]       - AHK object to serialize.
 *     outfile   [in, opt]  - The file to write to. If no absolute path is
 *                            specified, %A_WorkingDir% is used.
 *
 * Syntax (Deserialize):
 *     obj := SerDes( src )
 * Parameter(s):
 *     obj       [retval]   - An AHK object.
 *     src       [in]       - Either a 'SerDes()' formatted string or the path
 *                            to the file containing 'SerDes()' formatted text.
 *                            If no absolute path is specified, %A_WorkingDir%
 *                            is used.
 * Remarks:
 *     Serialized output is similar to JSON except for escape sequences which
 *     follows AHK's specification. Also, strings, numbers and objects are
 *     allowed as 'object/{}' keys unlike JSON which restricts it to string
 *     data type only.
 *     Object references, including circular ones, are supported and notated
 *     as '$n', where 'n' is the 1-based index of the referenced object in the
 *     heirarchy tree as it appears during enumeration (for-loop) OR as it
 *     appears from left to right (for string representation) as marked by an
 *     opening brace or bracket. See diagram below:
 *     1    2
 *     {"a":["string"], "b":$2} -> '$2' references the object stored in 'a'
 */
SerDes(src, out:="") {
	if IsObject(src) {
		ret := _sddumps(src)
		if (out == "")
			return ret
		if !(f := FileOpen(out, "w"))
			throw "Failed to open file: '" out "' for writing."
		bytes := f.Write(ret), f.Close()
		return bytes ;// return bytes written when dumping to file
	}
	if FileExist(src) {
		if !(f := FileOpen(src, "r"))
			throw "Failed to open file: '" src "' for reading."
		src := f.Read(), f.Close()
	}
	;// Begin de-serialization routine
	static is_v2 := (A_AhkVersion >= "2"), q := Chr(34)
	static push := Func(is_v2 ? "ObjPush"     : "ObjInsert")
	     , ins  := Func(is_v2 ? "ObjInsertAt" : "ObjInsert")
	     , set  := Func(is_v2 ? "ObjRawSet"   : "ObjInsert")
	     , pop  := Func(is_v2 ? "ObjPop"      : "ObjRemove")
	     , del  := Func(is_v2 ? "ObjRemoveAt" : "ObjRemove")
	static esc_seq := {   ;// AHK escape sequences
	(Join Q C
		"``": "``",       ;// accent
		(q):  q,          ;// double quote
		"n":  "`n",       ;// newline
		"r":  "`r",       ;// carriage return
		"b":  "`b",       ;// backspace
		"t":  "`t",       ;// tab
		"v":  "`v",       ;// vertical tab
		"a":  "`a",       ;// alert (bell)
		"f":  "`f"        ;// formfeed
	)}
	;// Extract string literals
	strings := [], i := 0, end := is_v2-1 ;// v1.1=-1, v2.0-a=0 -> SubStr()
	while (i := InStr(src, q,, i+1)) {
		j := i
		while (j := InStr(src, q,, j+1)) {
			str := SubStr(src, i+1, j-i-1)
			if (SubStr(str, end) != "``")
				break
		}
		if !j
			throw "Missing close quote(s)."
		src := SubStr(src, 1, i) . SubStr(src, j+1)
		z := 0
		while (z := InStr(str, "``",, z+1)) {
			ch := SubStr(str, z+1, 1)
			if InStr(q . "``nrbtvaf", ch)
				str := SubStr(str, 1, z-1) . esc_seq[ch] . SubStr(str, z+2)
			else throw "Invalid escape sequence: '``" . ch . "'" 
		}
		%push%(strings, str) ;// strings.Insert(str) / strings.Push(str)
	}
	;// Begin recursive descent to parse markup
	pos := 0
	, is_key := false
	, refs := [], kobj := []
	, stack := [tree := []]
	, is_arr := Object(tree, 1)
	, next := q "{[01234567890-"
	while ((ch := SubStr(src, ++pos, 1)) != "") {
		if InStr(" `t`n`r", ch)
			continue
		if !InStr(next, ch)
			throw "Unexpected char: '" ch "'"
		_obj := stack[1]
		;// Associative/Linear array opening
		if InStr("{[", ch) {
			val := {}, is_arr[val] := ch == "[", %push%(refs, &val)
			if is_key
				%ins%(kobj, 1, val), key := val
			is_arr[_obj] ? %push%(_obj, val) : %set%(_obj, key, is_key ? 0 : val)
			, %ins%(stack, 1, val), is_key := ch == "{"
			, next := q "{[0123456789-$" (is_arr[val] ? "]" : "}") ; (is_key ? "}" : "]")
			continue
		}
		;// Associative/Linear array closing
		else if InStr("}]", ch) {
			next := is_arr[stack[2]] ? "]," : "},"
			if (kobj[1] == %del%(stack, 1))
				key := %del%(kobj, 1), next := ":"
			continue
		}
		;// Token
		else if InStr(",:", ch) {
			if (_obj == tree)
				throw "Unexpected char: '" ch "' -> there is no container object."
			next := q "{[0123456789-$"
			, is_key := (!is_arr[_obj] && ch == ",")
			continue
		}
		;// String
		else if (ch == q) {
			val := %del%(strings, 1)
		}
		;// Number / Object reference
		else if (ch >= 0 && ch <= 9) || InStr("-$", ch) {
			if (is_ref := (ch == "$")) ;// object reference token
				pos += 1
			val := SubStr(src, pos, (SubStr(src, pos) ~= "[\]\}:,\s]|$")-1)
			if (Abs(val) == "")
				throw "Invalid number: " val
			pos += StrLen(val)-1, val += 0
			if is_ref {
				if !ObjHasKey(refs, val)
					throw "Invalid object reference: $" val
				val := Object(refs[val]), is_ref := false
			}
		}
		if is_key {
			key := val, next := ":"
			continue
		}
		is_arr[_obj] ? %push%(_obj, val) : %set%(_obj, key, val)
		, next := is_arr[_obj] ? "]," : "},"
	}
	return tree[1]
}
;// Helper function, serialize object to string -> internal use only
_sddumps(obj, refs:=false) { ;// refs=internal parameter
	static q := Chr(34)      ;// Double quote, for v1.1 & v2.0-a compatibility
	static esc_seq := {      ;// AHK escape sequences
	(Join Q C
		(q):  "``" . q,      ;// double-quote
		"`n": "``n",         ;// newline
		"`r": "``r",         ;// carriage return
		"`b": "``b",         ;// backspace
		"`t": "``t",         ;// tab
		"`v": "``v",         ;// vertical tab
		"`a": "``a",         ;// alert (bell)
		"`f": "``f"          ;// formfeed
	)}
	if IsObject(obj) {
		if !refs
			refs := {}
		if refs.HasKey(obj) ;// Object references, includes circular
			return "$" refs[obj] ;// return notation = $(index_of_object)
		refs[obj] := NumGet(&refs+4*A_PtrSize)+1

		for k in obj
			arr := (k == A_Index)
		until !arr
		str := "", len := NumGet(&obj+4*A_PtrSize)
		for k, v in obj {
			val := _sddumps(v, refs)
			str .= (arr ? val : _sddumps(k, refs) ":" val)
			    .  (A_Index < len ? "," : "")
		}
		return arr ? "[" str "]" : "{" str "}"
	}
	else if (ObjGetCapacity([obj], 1) == "")
		return obj
	i := 0
	while (i := InStr(obj, "``",, i+1))
		obj := SubStr(obj, 1, i-1) . "````" . SubStr(obj, i+=1)
	for k, v in esc_seq {
		/* StringReplace/StrReplace workaround routine for v1.1 and v2.0-a
		 * compatibility. TODO: Compare w/ RegExReplace()
		 */
		i := 0
		while (i := InStr(obj, k,, i+1))
			obj := SubStr(obj, 1, i-1) . v . SubStr(obj, i+=1)
	}
	return q . obj . q
}