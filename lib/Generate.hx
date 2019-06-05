package lib;

class Generate {
	public static function VersionString(version:String):String {
		return '== Hix Version $version by Pixelbyte Studios ==';
	}

	public static function Help(headerStart:String, validExtensions:Array<String>):String {
		var inst:String = "
 Hix is a utility that lets you to store compile settings inside of source files.
 Currently supported languages are: ::ValidExtensions::	
 Put the start header near the top of your source file and add desired compile args:
 //::HixHeader:: -main Main -neko example.n 
 If you want, you can put the args on multiple lines:
 //::HixHeader::
 //-main Main
 //-neko hi.n
 Or you can put it them a multi-line comment:
 /*
 ::HixHeader::
 -main Main
 -neko hi.n
 */
 
 Hix also supports multiple build configs.
 For example, in a haxe .hx file you can specify both cpp and neko target builds. 
 
 //::HixHeader:::target1 -main Main --no-traces -dce full -cpp bin
 //::HixHeader:::target2 -main HR --no-traces -dce full -neko hr.n
 
 Then invoke your desired build config by adding the name of the config (which
 in this case is either target1 or target2):
 hix Main.hx target1 <- Builds target1
 hix Main.hx target2 <- Builds target2
 
 Then compile by running:
 hix <inputFile>
 
 No more hxml or makefiles needed!
 
 Special arguments:
 ${filename} -> gets the name of the current file
 ${filenameNoExt} -> gets the name of the current file without the extension
 ${datetime} -> <optional strftime format specification>] ->Note not all strftime settings are supported
 ${datetime} -> without specifying a strftime format will output: %m/%e/%Y_%H:%M:%S
 
 You can also change the program that is executed with the args (by default it is haxe)
 by placing a special command BEFORE the start header:
 //::exe=<name of executable>

 Additionally, hix also supports embedded files:
 /*::tmpfile= [filename]
 file contents
 */
 Any build tasks referring to this filename will cause it to be created before executing the build
 After the build has completed, the file will be deleted unless the '-e' flag is specified. Temp files
 will not be created unless they are referred to in the build command

 Non temp files can also be generated as well:
 /*::genfile= [filename]
 file contents
 */
 =============================================================================
			";

		var params = {HixHeader: headerStart, ValidExtensions: validExtensions.join(" ")};
		var template = new haxe.Template(inst);
		return template.execute(params);
	}

	public static function Usage(version:String):String {
		var data:String = "
== Hix Version ::programVersion:: by Pixelbyte Studios ==
Hix.exe [flags] <inputFile> [buildName]			
available flags:
-v prints version info
-clean Cleans any intermediate files (currently for .c and .cpp src files only)
-l <inputFile> prints valid builds
-e don't delete generated tmp files
-ks <key:value> adds or changes a key/value pair to the hix.json config file
-kd <key> deletes the key from the hix.json config file
-kg <key> gets the value of the key from the hix.json config file
-h prints help
-u prints usage info	
-gen <filename> Generates a default hix header for the given filename via the extension. If the file exists and no hix header is found, it will be inserted. Otherwise the file will be created with the header.";
		var params = {programVersion: version};
		var template = new haxe.Template(data);
		return template.execute(params);
	}

	public static function DefaultConfig():String {
		return "{
    \"author\":null,
    \"setupEnv\" : null,
    \"editor\" : \"code\",
    \"hxHeader\":[
        \"//This program can be compiled with the Hix.exe utility\",
        \"::if (author != null):://Author: ::author::::else:://::end::\",
        \"::if (setupEnv != null):://::SetupKey:: ::setupEnv::::else:://::end::\",
        \"//::hix       -main ${filenameNoExt} ::if (SrcDir != null)::-cp ::SrcDir::::else::p::end:: -cpp bin --no-traces -dce full\",
        \"//::hix:debug -main ${filenameNoExt} ::if (SrcDir != null)::-cp ::SrcDir::::else::p::end:: -cpp bin\",
        \"//\"
    ],
    \"csHeader\":[
        \"//This program can be compiled with the Hix.exe utility\",
        \"::if (author != null):://Author: ::author::::else:://::end::\",
        \"::if (setupEnv != null):://::SetupKey:: ::setupEnv::::else:://::end::\",
        \"//::hix -optimize -out:${filenameNoExt}.exe ${filename}\",
        \"//::hix:debug -define:DEBUG -out:${filenameNoExt}.exe ${filename}\",
        \"//\"
        ],
    \"csBody\":[
      \"public class ::ClassName::\",
      \"{\",
      \"    static void Main(string[] args)\",
      \"    {\",
      \"\",
      \"    }\",
      \"}\"  
    ],
    \"cHeader\":[
        \"//This program can be compiled with the Hix.exe utility\",
        \"::if (author != null):://Author: ::author::::else:://::end::\",
        \"::if (setupEnv != null):://::SetupKey:: ::setupEnv::::else:://::end::\",
        \"//::incDirs=\",
        \"//::libDirs=\",
        \"//::libs=\",
        \"//::defines=_CRT_SECURE_NO_WARNINGS \",
        \"//::hix\",
        \"//\"
        ]
    }";
	}

	public static function Template(textArray:Array<String>, macros:Dynamic):String {
		if (textArray == null)
			return null;
		var template = new haxe.Template(textArray.join("\n"));
		try {
			return template.execute(macros);
		} catch (ex:Dynamic) {
			Log.error(new String(ex));
			return null;
		}
	}
}
