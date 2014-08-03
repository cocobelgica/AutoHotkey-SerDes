# SerDes.ahk
#### Serialize / de-serialize an [AutoHotkey](http://ahkscript.org) [object](http://ahkscript.org/docs/Objects.htm) structure.
*Tested on AutoHotkey **[v1.1.15.03](http://ahkscript.org/boards/viewtopic.php?p=22836#p22836)** and **[v2.0-a049](http://ahkscript.org/boards/viewtopic.php?p=22371#p22371)***

- - -


### Serialize
**Syntax**

    str   := SerDes( obj )
    bytes := SerDes( obj [, outfile ] )
**Parameters**

    str      [retval]   - String representation of the object
    bytes    [retval]   - Bytes written to 'outfile'.
    obj      [in]       - AHK object to serialize.
    outfile  [in, opt]  - The file to write to. If no absolute path is specified, %A_WorkingDir% is used.
- - -
### Deserialize
**Syntax**

    obj   := SerDes( src )
**Parameters**

    obj      [retval]   - An AHK object
    src      [in]       - Either a 'SerDes()' formatted string or the path to the file containing 'SerDes()' formatted text.
- - -
## Remarks:
* Serilaized output is similar to [JSON](http://json.org/) except for escape sequences which follows [AHK's specification](http://ahkscript.org/docs/commands/_EscapeChar.htm#Escape_Sequences_when_accent_is_the_escape_character). Also, strings, numbers and objects are allowed as `object/{}` keys unlike JSON which restricts it to string data type only.
* Object references, including circular ones, are supported and notated as `$n`, where `n` is the **1-based** index of the referenced object in the heirarchy tree as it appears during enumeration *(for-loop)* OR as it appears from left to right *(for string representation)* as marked by an opening brace`{` or bracket`[`.
    * `{ "key1": ["Hello World"], "key2": $2 }` -> `$2` references the object stored in `key1`