import haxe.ds.StringMap;
import haxe.Template;
import sys.io.File;
import haxe.io.Path;
import sys.FileSystem;
// Grab our supporting classes
import lib.*;

//
// Description:
// Hix is a utility that enables compiling a Haxe source file without having a
// build.hxml file or having to specify command line args every time you want to do a build.
//
// Author: Pixelbyte studios
// Date: June 2019
//
// ::hix       -main ${filenameNoExt} -cp src -cpp bin -D gen_cfg -D analyzer --no-traces -dce full
// ::hix:debug -main ${filenameNoExt} -cp src -cpp bin
// ::hix:run   -main Hix -cp src --interp
//

enum FileGenType {
	AllNonTemp;
	MatchingKeys;
}

enum FileDelType {
	AllNonTemp;
	AllTemp;
	All;
}

// .c. .cpp, .cs, .hx, .js, .ts
// comments
//	single line: //
//	multiline: /* */
// .lua
// single line: --
// multiline: --[[  ]]--

class Hix {
	static inline var VERSION = "0.52";
	// The header string that must be present in the file so we know to parse the compiler args
	static inline var COMMAND_PREFIX = "::";
	static inline var HEADER_START = COMMAND_PREFIX + "hix";
	static inline var SPECIAL_CHAR = "$";
	static inline var HX_EXT = "hx";
	static inline var DEFAULT_BUILD_NAME = "default";
	static inline var OBJ_DIR = "obj";
	// Special hix.json config keys
	static inline var KEY_AUTHOR = "author";
	static inline var KEY_SETUP_ENV = "setupEnv";
	static var DEFAULT_CFLAGS = '/nologo /EHsc /GS /GL /Gy /sdl /O2 /WX /Fo:${OBJ_DIR}\\';
	static inline var DEFAULT_C_OUTPUT_ARGS = "${cflags} ${filename} ${defines} ${incDirs} /link /LTCG ${libDirs} ${libs} /OUT:${filenameNoExt}.exe";
	static var ExtMap:Map<String, String> = [
		"hx" => "haxe.exe",
		"cs" => "csc.exe",
		"c" => "cl.exe",
		"cpp" => "cl.exe",
		"js" => "node.exe",
		"ts" => "tsc.exe",
		"lua" => "lua.exe"
	];
	static var CommentType:StringMap<Comment> = [
		"default" => new Comment(~/^\s*\/\//, ~/\/\*/, ~/\*\//),
		"lua" => new Comment(~/^--/, ~/--\[\[/, ~/]]--/)
	];
	// returns the name of the system this is running on
	public static var OS = Sys.systemName();
	// The executable key
	static inline var KEY_EXE = "exe";

	// This is where we store any keyValue pairs we find before the hix header is found
	var keyValues:Map<String, String>;
	// This allows us to embed files into an existing file and hix will extract it
	// to a temporary file for processing
	var embeddedFiles:Map<String, EmbeddedFile>;
	// If true, then Hix will delete any generated embedded files after execution
	var deleteGeneratedEmbeddedFiles:Bool = true;

	// Read-only property for the current state of the parser
	public var Succeeded(get, null):Bool = false;
	public var FoundHeader(null, default):Bool = false;
	public var StateName(get, null):String;
	
	function get_StateName():String {
		var result:String = "null";

		if (stateFunction != null) {
			for (name in Reflect.fields(this)) {
				var field:Dynamic = Reflect.field(this, name);
				if (field.isFunction() && Reflect.compareMethods(stateFunction, field)) {
					result = name;
					break;
				}
			}
		}
		return result;
	}

	function get_Succeeded():Bool {
		return (stateFunction == StateParseEmbeddedFile || stateFunction == StateFindOtherCmds || stateFunction == StateSuccess);
	}

	// The comment analyzer for the file we're looking at
	var commentAnalyzer:Comment;
	// true if we are currently in a comment, false otherwise
	var inComment:Bool = false;
	// Tells us if we are in a multi-line comment
	var multilineComment:Bool = false;
	// The name of the file under examination
	var filename:String;
	// The type of file we're looking at. I.e cs c hx js ts cpp, etc
	var fileType:String;
	// The current line of text from the input file
	var text:String;
	var currentBuildName:String = DEFAULT_BUILD_NAME;
	var buildMap:Map<String, Array<String>>;

	static function main():Int {
		var inputFile:String = null;
		var inputBuildName:String = DEFAULT_BUILD_NAME;

		// Get the current working directory
		var cwd = Sys.getCwd();

		if (Sys.args().length == 0) {
			Log.log(Generate.Usage(VERSION));
			return 1;
		}

		// Get any command line args
		var args:Array<String> = Sys.args();

		// Strip any bool flags from args
		var flags = Util.ParseArgOptions(args);
		var config:Config = Config.Create();

		if (!config.Exists) {
			File.saveContent(config.FullPath, Generate.DefaultConfig());
			config = Config.Create();
			Log.log('[Hix] Creating new Config file at: ${config.FullPath}');
		}

		// Check for any command line switches here
		// See Generate.Usage() for documentation on these flags
		if (Util.ProcessFlag("h", flags)) {
			var validExt:Array<String> = new Array<String>();
			for (e in ExtMap)
				validExt.push(e);
			Log.log(Generate.Help(HEADER_START, validExt));
			return 0;
		} else if (Util.ProcessFlag("u", flags)) {
			Log.log(Generate.Usage(VERSION));
			return 0;
		} else if (Util.ProcessFlag("v", flags)) {
			Log.log(Generate.VersionString(VERSION));
			return 0;
		} else if (Util.ProcessFlag("ks", flags)) {
			// The argument should be the very next one in the args list
			if (args.length == 0 || args[0].indexOf(':') == -1) {
				Log.error('Expected a key/value in the form key:value');
				return 1;
			} else {
				var kv = args[0].split(':');
				var key = StringTools.trim(kv[0]);
				var val = StringTools.trim(kv[1]);
				if (kv.length < 2 || val.length == 0) {
					Log.error('Expected a key/value in the form key:value');
					return 1;
				} else {
					config.Set({key: key, val: val});
					config.Save();
					return 0;
				}
			}
		} else if (Util.ProcessFlag("kd", flags)) {
			// The argument should be the very next one in the args list
			var valid = ~/[A-Za-z_]+/i;
			if (args.length == 0 || !valid.match(args[0])) {
				Log.error('Expected the name of a key!');
				return 1;
			} else {
				var key = StringTools.trim(args[0]);
				config.Set({key: key, val: null});
				config.Save();
				Log.log('Key: ${key} deleted from ${config.Filename}');
				return 0;
			}
		} else if (Util.ProcessFlag("kg", flags)) {
			// The argument should be the very next one in the args list
			var valid = ~/[A-Za-z_]+/i;
			if (args.length == 0 || !valid.match(args[0])) {
				Log.error('Expected the name of a key!');
				return 1;
			} else {
				var key = StringTools.trim(args[0]);
				var val = config.Get(key);
				if (val == null)
					Log.warn('[Hix] keyname "$key" not found');
				else
					Log.log('[Hix] found key:$key => $val');
				return 0;
			}
		}
		if (Util.ProcessFlag("gen", flags)) {
			// Setup Template globals (these have lower priority than the macros passed into template.execute())
			Reflect.setField(Template.globals, 'SetupKey', '::setupEnv =');

			var filePath = Util.GetFirstFilenameFromArgs(args, false);
			if (filePath != null) {
				var ext = Util.GetExt(filePath);
				var header_template = config.Get(ext + "Header");
				var body_template = config.Get(ext + "Body");
				if (header_template == null) {
					Log.warn('Unable to find ${ext + "Header"} key in ${config.Filename}');
				}
				if (body_template == null) {
					Log.warn('Unable to find ${ext + "Body"} key in ${config.Filename}');
				}

				if(header_template == null && body_template == null) {
					Log.error('Unable to generate $filePath. Could not find ${ext + "Header"} or ${ext + "Body"} entries in ${config.Filename}');
					return 1;
				}

				var header_content = Generate.Template(header_template, {author: config.Get(KEY_AUTHOR), setupEnv: config.Get(KEY_SETUP_ENV)});
				var body_content = Generate.Template(body_template, {ClassName: new Path(filePath).file});
				if (!FileSystem.exists(filePath)) {
					var sb:StringBuf = new StringBuf();
					if (header_content != null)
						sb.add(header_content);
					if (body_content != null){
						sb.addChar('\n'.code);
						sb.add(body_content);
					}
					if(sb.length > 0)
						File.saveContent(filePath, sb.toString());
					else 
						Log.error('Unable to generate $filePath. Content was empty!');
				} else { // The file exists so we must do more
					var existingText = File.getContent(filePath);
					// Search the file for a hix header
					if (existingText.indexOf(HEADER_START) > -1) {
						Log.warn('[Hix] found an existing header in "$filePath" aborted header insert');
					} else {
						try {
							File.saveContent(filePath, header_content + existingText);
						} catch (ex:Dynamic) {
							Log.error(new String(ex));
						}
					}
				}

				//If we find a '.' then try to open the new file in the editor if it is configured
				var dot = Util.ParseFirstNonFilename(args);
				if(dot == "."){
					var editor = config.Get("editor");
					if (editor != null){
						return Sys.command('$editor $filePath');
					}
				}
			}
			return 0;
		}

		// Should we not delete generatedEmbeddedFiles?
		var deleteEmbeddedFiles:Bool = !Util.ProcessFlag("e", flags);

		// look for the first VALID filename from the args
		if (inputFile == null) {
			inputFile = Util.GetFirstFilenameFromArgs(args);

			if (inputFile == null) {
				// look for any .hx file in the current directory
				inputFile = Util.FindFirstFileInValidExts(cwd, ExtMap);
				if (inputFile == null) {
					Log.log(Generate.Usage(VERSION));
					return 1;
				} else
					Log.log('Trying file: $inputFile');
			}
		}

		// See if there is a build name specified
		inputBuildName = Util.ParseFirstNonFilename(args);
		if (inputBuildName == null)
			inputBuildName = DEFAULT_BUILD_NAME;

		// Are we missing an input file?
		if (inputFile == null) {
			Log.error('Unable to find any valid files!');
			return 1;
		}

		// Check if file exists
		if (!FileSystem.exists(inputFile)) {
			Log.error('File: $inputFile does not exist!');
			return 1;
		}

		// Start with the default comment analyzer
		var commentAnalyzer = CommentType.get("default");
		var ext = Util.GetExt(inputFile);
		if (CommentType.exists(ext))
			commentAnalyzer = CommentType.get(ext);

		// Create our 'hix' instance
		var h = new Hix(commentAnalyzer, deleteEmbeddedFiles);

		if (Util.ProcessFlag("clean", flags)) {
			if (h.fileType == "c" || h.fileType == "cpp") {
				if (FileSystem.exists(OBJ_DIR)) {
					Log.log('[Hix] Cleaning ${OBJ_DIR} directory');
					Util.DeleteDir(OBJ_DIR);
				} else {
					Log.log('[Hix] No ${OBJ_DIR} directory exists');
				}
			} else {
				Log.log('[Hix] Currently only supports cleaning for .c and .cpp files.');
			}
			return 1;
		}

		// Now parse the file and try to do something
		h.ParseFile(inputFile);

		if (Util.ProcessFlag("l", flags)) {
			if (h.buildMap.keys().hasNext()) {
				Log.log('Available Build labels in: $inputFile');
				Log.log('-----------------------');
				for (buildName in h.buildMap.keys()) {
					Log.log('$buildName');
				}
			} else {
				Log.error('No build instructions found in: $inputFile');
			}
			return 1;
		}

		if (h.Succeeded) {
			trace("File successfully parsed. Executing...");
			return h.Execute(inputBuildName, config);
		} else if (!h.FoundHeader) {
			Log.error("Unable to find a hix header!");
			return 1;
		} else {
			trace('Parser State: ${h.StateName}');
			Log.error("There was a problem!");
			return 1;
		}
	}

	public function new(analyzer:Comment, deleteGeneratedFiles:Bool = true) {
		commentAnalyzer = analyzer;
		buildMap = new Map<String, Array<String>>();
		keyValues = new Map<String, String>();
		embeddedFiles = new Map<String, EmbeddedFile>();
		deleteGeneratedEmbeddedFiles = deleteGeneratedFiles;

		// Setup some defaults for C/C++ builds
		keyValues["cflags"] = DEFAULT_CFLAGS;
	}

	//
	// Executes the command that was constructed by Calling ParseFile
	//
	public function Execute(buildName:String, cfg:Config):Int {
		var usedEmbeddedTmpFiles:Array<String> = new Array<String>();

		if (!buildMap.exists(buildName) || buildMap[buildName].length == 0) {
			Log.error('[Hix] No compiler args found for: $buildName');
			return -1;
		} else {
			// Look for the exe to call for building
			var exe:String = keyValues[KEY_EXE];
			if (exe == null || exe.length == 0) {
				Log.error('Exe is unknown or was not specified using //::exe\nExiting...');
				return -1;
			}

			// Check if there are any pre args
			var args:List<String> = new List<String>();
			if (keyValues.exists("preCmd")) {
				Log.log('Appending PreCmd: ${keyValues["preCmd"]}');
				args.add(keyValues["preCmd"]);
			}

			// Do special things for certain filetypes
			// create an obj folder for .c or cpp files if one doesn't exist
			if (fileType == "c" || fileType == "cpp") {
				if (!FileSystem.exists(OBJ_DIR))
					FileSystem.createDirectory(OBJ_DIR);
			}

			// See if the KEY_EXE is in the filepath. If not, check for a setupEnv key/value pair
			// and if found, assume that the environment needs to be setup by calling the setupEnv command
			if (Util.WhereIsFile(exe) == null) {
				if (keyValues.exists("setupEnv")) {
					trace('[Hix] Unable to find key "${KEY_EXE}" in ${cfg.Filename}');

					var setupCmd = keyValues["setupEnv"];
					if (Util.WhereIsFile(setupCmd) == null) {
						Log.warn('Unable to find the setupEnv command :${setupCmd}. Ignoring...');
					} else {
						trace('[Hix] Found setupEnv key. Appending value to command.');
						args.add(setupCmd + "&&");
					}
					// Sys.command(keyValues["setupEnv"]);
					// Config.Set({key : exe + "Path", val : WhereIsFile(exe)});
				} else {
					trace('[Hix] Unable to find setupEnv key.');
					Log.error('Unable to find the executable: ${exe}');
					return -1;
				}
			}

			// Add the actual command
			args.add(exe);

			// Add the build args
			for (a in buildMap[buildName])
				args.add(a);

			// Check for references to any embedded files in the source file
			trace('Embedded files in $filename: ${Lambda.count(embeddedFiles)}');
			trace('Generate temp Files found in build args');
			for (text in args) {
				// Windows filenames are case insensitive
				// if(OS == "Windows") text = text.toLowerCase();

				// search for any embedded files in the args and if found, create them and add them to a list
				// to be deleted after the run is finished
				for (key in embeddedFiles.keys()) {
					var embedded = embeddedFiles[key];
					// Skip any non-temp file and any that we already know are used
					if (!embedded.tmpFile || usedEmbeddedTmpFiles.indexOf(embedded.name) > -1)
						continue;

					// Is this file referenced ?
					if (text.indexOf(embedded.name) > -1) {
						usedEmbeddedTmpFiles.push(embedded.name);
					}
				}
			}

			GenerateEmbeddedFiles(MatchingKeys, usedEmbeddedTmpFiles);
			GenerateEmbeddedFiles(AllNonTemp);

			Log.log('[Hix] Running build label: $buildName');
			Log.log(args.join(" ") + "\n");
			var retCode = Sys.command(args.join(" "));
			// var retCode = Sys.command(exe, args);

			// Delete any temp-create embedded files
			if (usedEmbeddedTmpFiles.length > 0) {
				if (deleteGeneratedEmbeddedFiles) {
					DeleteEmbeddedFiles(AllTemp);
				} else {
					for (name in usedEmbeddedTmpFiles) {
						Log.log('[Hix] Temp file not deleted: $name');
					}
				}
			}
			return retCode;
		}
	}

	function DeleteEmbeddedFiles(mode:FileDelType) {
		for (key in embeddedFiles.keys()) {
			var embedded = embeddedFiles[key];
			if (mode == AllNonTemp && embedded.tmpFile)
				continue;
			else if (mode == AllTemp && !embedded.tmpFile)
				continue;

			try {
				if (embedded.tmpFile && embedded.Exists())
					embedded.Delete();
			} catch (ex:Dynamic) {
				Log.error('Unable to delete embedded file: ${embedded.name}!');
			}
		}
	}

	function GenerateEmbeddedFiles(mode:FileGenType, keysToGenerate:Array<String> = null) {
		var type:String = if (mode == AllNonTemp) "file" else "tmp file";

		// Generate ONLY the non-tmp files found
		trace('Generate embedded ${type}s');
		for (key in embeddedFiles.keys()) {
			var embedded = embeddedFiles[key];

			// Skip ALL temp files
			if (mode == AllNonTemp && embedded.tmpFile)
				continue;
			else if (mode == MatchingKeys && (keysToGenerate == null || keysToGenerate.indexOf(embedded.name) == -1))
				continue;

			if (embedded.Exists())
				Log.warn('Embedded $type: ${embedded.name} already exists. Ignoring embedded version.');
			else if (embedded.Generate()) {
				Log.log('[Hix] Embedded $type generated: ${embedded.name}');
			} else {
				Log.error('[Hix] unable to generate embedded $type: ${embedded.name}');
			}
		}
	}

	var stateFunction:Void->Bool;

	function StateFindHeader():Bool {
		var whitespace = ~/^\s+$/g;
		currentBuildArgs = IsStartHeader();
		if (currentBuildArgs != null) {
			trace("[Hix] Header Found!");
			// Once the header is found, we begin searching for build arguments
			// Note: Once the search for build args has begun, it will stop
			// once the 1st non-comment line is reached.
			trace('[Hix] Getting build args for: $currentBuildName');

			stateFunction = StateFindArgs;
		} else {
			// Look for any Pre-Header key/values
			var t = ParseHeaderKeyValue();
			if (t != null) {
				keyValues[t.key] = t.val;
				if (t.key == KEY_EXE)
					Log.log('[Hix] exe changed to: ${t.val}');
				else if (t.key == "incDirs") {
					var v = t.val.split(" ");
					v = v.filter(function(str) return str.length > 0 && !whitespace.match(str));
					if (v.length == 0)
						keyValues[t.key] = "";
					else {
						v[0] = "/I" + v[0];
						keyValues[t.key] = v.join(" /I");
					}
				} else if (t.key == "libDirs") {
					var v = t.val.split(" ");
					v = v.filter(function(str) return str.length > 0 && !whitespace.match(str));
					if (v.length == 0)
						keyValues[t.key] = "";
					else {
						v[0] = "/LIBPATH:" + v[0];
						keyValues[t.key] = v.join(" /LIBPATH:");
					}
				} else if (t.key == "defines") {
					var v = t.val.split(" ");
					v = v.filter(function(str) return str.length > 0 && !whitespace.match(str));
					if (v.length == 0)
						keyValues[t.key] = "";
					else {
						v[0] = "/D" + v[0];
						keyValues[t.key] = v.join(" /D");
					}
				} else if (t.key == "libs") {
					var v = t.val.split(" ");
					v = v.filter(function(str) return str.length > 0 && !whitespace.match(str));
					if (v.length == 0)
						keyValues[t.key] = "";
					else {
						keyValues[t.key] = v.map(function(str) {
							if (str.indexOf(".") > -1)
								return str;
							else
								return str + ".lib";
						}).join(" ");
					}
				}
			}
		}
		return true;
	}

	function StateFindArgs():Bool {
		if (!inComment && currentBuildArgs.length == 0) // Couldn't find anything
		{
			Log.error("Unable to find any compiler args in the header!");
			stateFunction = StateFail;
		} else if (!inComment && currentBuildArgs.length > 0) // Found something
		{
			trace("[Hix] Success. Found compiler args");
			CreateBuilder(currentBuildName, currentBuildArgs);
			// state = State.StateSuccess;
			stateFunction = StateFindOtherCmds;
			trace("[Hix] Searching for other commands");
			// break;
		} else // We're in a comment
		{
			trace("[Hix] Searching a comment");
			var newArgs = IsStartHeader();
			if (newArgs != null) {
				trace("[Hix] Success");
				// Since it looks like we're in a start header, create any builder we had previously stored
				CreateBuilder(prevBuildName, currentBuildArgs);
				// Now switch to this new current one
				currentBuildArgs = newArgs;
				prevBuildName = currentBuildName;

				trace("[Hix] Getting args for: " + currentBuildName);
			} else {
				// we are in a comment, lets see if there is text here if there is we assume it is a command arg
				// If, however, the comment is empty, then move on
				var grabbedArgs = GrabArgs(text);
				if (grabbedArgs != null && grabbedArgs.length > 0)
					currentBuildArgs = currentBuildArgs.concat(grabbedArgs);
				// else{
				// 	Log.error('Unable to grab args. Offending text:\n${text}');
				// 	state = State.StateFail;
				// }
			}
		}
		return true;
	}

	function StateFindOtherCmds():Bool {
		if (inComment) {
			// Look for any other keyvalue commands
			var t = ParseHeaderKeyValue();
			if (t != null) {
				trace('key: ${t.key}');
				if (t.key == "tmpfile" || t.key == "genfile") {
					if (t.val == "" || t.val == null) {
						Log.error('${line} Must specify a name for the embedded file!');
						stateFunction = StateFail;
					} else {
						Log.log('[Hix] embedded file found: ${t.val}');
						var filename:String = "";
						// if(OS == "Windows")
						// 	filename = t.val.toLowerCase();
						// else
						filename = t.val;
						stateFunction = StateParseEmbeddedFile;
						currentFile = new EmbeddedFile(filename, t.key == "tmpfile");
					}
				}
			}
		}
		return true;
	}

	function StateParseEmbeddedFile():Bool {
		if (!inComment) {
			if (currentFile.contents.length > 0) {
				if (embeddedFiles.exists(currentFile.name))
					Log.error('Embedded file ${currentFile.name} already exists in $filename! Skipping...');
				else
					embeddedFiles.set(currentFile.name, currentFile);
				currentFile = null;
			}

			stateFunction = StateFindOtherCmds;
		} else {
			// Make sure this is NOT the end of a multiline comment
			// The multiline comment ending tag '*/' must be placed on a separate line
			if (!commentAnalyzer.IsMultiEnd(text)) {
				if (currentFile.contents.length > 0)
					currentFile.contents.add("\n");
				currentFile.contents.add(Std.string(text));
			}
		}
		return true;
	}

	function StateSuccess():Bool {
		return false;
	}

	function StateFail():Bool {
		return false;
	}

	var currentBuildArgs:Array<String> = null;
	// What file line we are on
	var line:Int;
	// Store the current embedded file we are parsing (if there is one) in here
	var currentFile:EmbeddedFile = null;
	var prevBuildName:String = DEFAULT_BUILD_NAME;

	//
	// This function parses the input file to get the command line args in order to run the haxe compiler
	//
	public function ParseFile(fileName:String) {
		// Get the file's extension
		fileType = Util.GetExt(fileName);
		if (fileType == null)
			fileType == "";
		else
			fileType == fileType.toLowerCase();
		Log.log('file ext: $fileType');

		// Set the default name of the executable to run (this can be changed by placing '//::exe=newExe.exe' before the start header)
		if (ExtMap.exists(fileType))
			keyValues[KEY_EXE] = ExtMap[fileType];
		else
			keyValues[KEY_EXE] = "";

		Log.log('picked exe: ${keyValues[KEY_EXE]}');

		// What line are we on
		line = -1;
		prevBuildName = DEFAULT_BUILD_NAME;
		inComment = false;
		multilineComment = false;
		filename = fileName;
		currentFile = null;

		// Try to open the file in text mode
		stateFunction = StateFindHeader;
		var reader = File.read(fileName, false);
		try {
			trace("[Hix] Searching for a header..");
			while (true) {
				text = reader.readLine();
				line++;

				// Update the multiline comment state
				CheckComment();
				if (!stateFunction())
					break;
			}
		} catch (ex:haxe.io.Eof) {}
		reader.close();

		if (currentFile != null) {
			embeddedFiles.set(currentFile.name, currentFile);
			currentFile = null;
		}
	}

	function ProcessSpecialCommands(buildArgList:Array<String>) {
		for (i in 0...buildArgList.length) {
			buildArgList[i] = ProcessSpecialCommand(buildArgList[i]);
		}
	}

	// DO any string search/replace here
	// A special string starts with '$' and can contain any chars except for whitespace
	// var sp = new EReg("^\\$([^\\s]+)", "i");
	var sp = new EReg("\\${([^\\]]+)}", "i");

	function ProcessSpecialCommand(text:String, key:String = null, returnEmptyIfNotFound:Bool = false):String {
		if (sp.match(text)) {
			// grab the special text. Split it by the '=' sign
			// so any parameters come after the =

			text = sp.map(text, function(r) {
				var matched = r.matched(1);
				// Process special commands here
				switch (matched) {
					case "filename":
						return filename;
					// Filename without the extension
					case "filenameNoExt":
						return new Path(filename).file;
					case "datetime":
						var date = Date.now();
						var cmd = matched.split('=');
						// No date parameters? Ok, just do defaul Month/Day/Year
						if (cmd.length == 1)
							return DateTools.format(date, "%m/%e/%Y_%H:%M:%S");
						else
							return DateTools.format(date, cmd[1]);
					default:
						if (keyValues.exists(matched)) {
							if (matched == key) {
								Log.error('Recursive key reference detected: ${key}');
								return r.matched(0);
							} else
								return keyValues.get(matched);
						} else {
							if (returnEmptyIfNotFound)
								return "";
							else
								return r.matched(0);
						}
				}
			});
		}
		return text;
	}

	function CreateBuilder(buildName:String, args:Array<String>) {
		trace('Create builder for $buildName\n');

		if (buildMap.exists(buildName)) {
			Log.error('Found duplicate build name: $buildName in $filename!');
			stateFunction = StateFail;
			return;
		}

		// Now process any special commands
		ProcessSpecialCommands(args);

		// Add this map to our list of build configs
		buildMap[buildName] = args;
	}

	// Looks for the start header string
	// returns: null if no header found or a new args array
	//
	function IsStartHeader():Array<String> {
		// If we are not in a comment,or there is no text return
		if (!inComment)
			return null;

		trace('$text');
		var header = new EReg(HEADER_START + "(:\\w+)?\\s*([^\\n]*)$", "i");

		// See if there is any stuff after the header declaration
		if (header.match(text)) {
			var isBlank = ~/^\s*$/;

			// Did we find a buildName?
			if (header.matched(1) != null && !isBlank.match(header.matched(1)) && header.matched(1).length > 1)
				currentBuildName = header.matched(1).substr(1);
			else
				currentBuildName = DEFAULT_BUILD_NAME;

			if (!isBlank.match(header.matched(2))) {
				// Add this arg to our args arry and trim any whitespace
				return GrabArgs(StringTools.rtrim(header.matched(2)));
			} else {
				trace('[Hix] Unable to find args for ${currentBuildName}');
				if (fileType == "c" || fileType == "cpp") {
					trace('[Hix] Settings default args for .c|.cpp file for ${currentBuildName}:\n${DEFAULT_C_OUTPUT_ARGS}');
					return GrabArgs(DEFAULT_C_OUTPUT_ARGS);
				} else {
					trace('[Hix] Args were empty and no default args found for ${currentBuildName}');
					return new Array<String>();
				}
			}
		}
		return null;
	}

	// Grabs the compiler arguments from the given text
	//
	function GrabArgs(txt:String):Array<String> {
		var isBlank = ~/\s*^\/*\s*$/;

		if (isBlank.match(txt))
			return null;
		var args:Array<String> = new Array<String>();

		var remhdr = new EReg("^\\s*" + HEADER_START, "i");
		var remcomm = ~/\s*\/\//;
		txt = remcomm.replace(txt, "");
		txt = remhdr.replace(txt, "");
		txt = StringTools.trim(txt);

		var parsedArgs = ParseSepString(txt, " ");
		for (a in parsedArgs) {
			args.push(a);
		}

		if (args.length > 0)
			return args;
		else
			return null;
	}

	//
	// Look for any key value declarations
	//
	function ParseHeaderKeyValue():KeyValue {
		// If we are not in a comment, return
		if (!inComment)
			return null;
		var cmd = new EReg(COMMAND_PREFIX + "\\s*([^\\n]*)$", "i");
		var keyVal = new EReg("\\s*([A-Za-z_][A-Za-z0-9_]+)\\s*=\\s*([^\\n]+)$", "i");
		if (cmd.match(text) && cmd.matched(1).indexOf('=') > -1) {
			if (keyVal.match(cmd.matched(1))) {
				var key = StringTools.rtrim(keyVal.matched(1));
				var val = ProcessSpecialCommand(StringTools.rtrim(keyVal.matched(2)), key);
				trace('[Hix] Found key value pair: ${key} = ${val}');
				return {key: key, val: val};
			} else
				return null;
		} else
			return null;
	}

	// Looks for single and multi-line comments
	//
	function CheckComment() {
		// if we weren't in a comment, see if we are now
		// Otherwise see if we are out of the comment
		if (!multilineComment) {
			multilineComment = commentAnalyzer.IsMultiStart(text) && !commentAnalyzer.IsMultiEnd(text);

			// See if we have a line comment
			inComment = multilineComment || commentAnalyzer.IsSingle(text);
		} else {
			multilineComment = !commentAnalyzer.IsMultiEnd(text);

			// even if the multiline comment ends, this line is still a comment
			inComment = true;
		}
	}

	//
	// This parses a string separated by the given delim and deals with quoted values
	//
	static function ParseSepString(text:String, delim:String, removeQuotes:Bool = true):Array<String> {
		var cols:Array<String> = new Array<String>();
		var start = 0;
		text = StringTools.trim(text);
		var end = text.length;
		while (start < end) {
			if (text.charAt(start) == '"') // Quoted value
			{
				var endQuote = text.indexOf('"', start + 1);
				if (endQuote == -1)
					throw("[Hix] Parse Error: Expected a matching \"" + text);
				else if (text.charAt(endQuote + 1) == '"') {
					endQuote++;
					endQuote = text.indexOf('"', endQuote + 1);

					while (text.charAt(endQuote + 1) == '"')
						endQuote++;
				}

				if (removeQuotes) {
					cols.push(text.substr(start + 1, endQuote - (start + 1)));
					// trace("[Hix] DQ: " + text.substr(start + 1, endQuote - (start + 1)));
				} else {
					cols.push(text.substr(start, endQuote + 1 - start));
					// trace("[Hix] DQ: " + text.substr(start , endQuote - start));
				}
				start = endQuote + 1;
			} else if (text.charAt(start) == "'") { // Single Quote value
				var endQuote = text.indexOf("'", start + 1);

				if (endQuote == -1)
					throw("[Hix] Parse Error: Expected a matching '\n" + text);

				if (removeQuotes) {
					cols.push(text.substr(start + 1, endQuote - (start + 1)));
					// trace("[Hix] Q: " + text.substr(start + 1, endQuote - (start + 1)));
				} else {
					cols.push(text.substr(start, endQuote + 1 - start));
					// trace("[Hix] Q: " + text.substr(start, endQuote - start ));
				}

				start = endQuote + 1;
			} else if (text.charAt(start) == " ")
				start++;
			else if (text.charAt(start) == delim) {
				start++;
				// Check and see if it is a null value
				while (start < end && text.charAt(start) == " ")
					start++;
				if (text.charAt(start) == delim) {
					// An empty column
					// cols.push("");
				}
			} else {
				var lastChar = text.indexOf(delim, start);
				if (lastChar == -1)
					lastChar = end;
				if (lastChar - start > 0) {
					cols.push(text.substr(start, lastChar - start));
					// trace(text.substr(start, lastChar - start));
					start = lastChar;
				}
			}
		}
		return cols;
	}

	public function PrintValidBuilds() {
		Sys.println("Valid Builds");
		Sys.println("============");
		for (key in buildMap.keys()) {
			Sys.println(key);
		}
	}
}
