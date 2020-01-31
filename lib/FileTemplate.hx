package lib;

import haxe.io.Path;
import haxe.ds.StringMap;
import sys.FileSystem;
import sys.io.File;

class FileTemplate {
	static inline var HEADER_ONLY_SUFFIX = "_hdr";

	var templateDir:String;
	var templateMap:StringMap<String>;

	public var TemplateDir(get, null):String;

	function get_TemplateDir()
		return templateDir;

	public function new(template_dir:String) {
		templateDir = Path.join([Path.directory(Sys.programPath()), template_dir]);
    }

	public function Init():StringMap<String> {
		if (!FileSystem.exists(templateDir)) {
			Log.warn('Template directory: ${templateDir} does not exst. Creating...');
			// TODO: Create
			FileSystem.createDirectory(templateDir);
		}

		// Assume ALL files in this directory are template files
		var files = FileSystem.readDirectory(templateDir);
		templateMap = new StringMap<String>();
		for (file in files){
			templateMap.set(Path.withoutExtension(file), Path.join([templateDir, file]));
        }
		return templateMap;
	}

	public function TemplateExists(key:String):Bool {
		return templateMap.exists(key);
	}

	public function GenerateFile(type:String, filePath:String, header_start:String, macros:Dynamic):Bool {
		if (!templateMap.exists(type)) {
			Log.error('A template of type ${type} was not found in ${templateDir}!');
			return false;
		}

        var templateFilePath = templateMap.get(type);
        trace('Template FilePath: ${templateFilePath}');
        var ext = Util.GetExt(templateFilePath);
        filePath = Util.SetExt(filePath, ext);
		var template = File.getContent(templateFilePath);
		var isHeaderOnly = StringTools.endsWith(templateFilePath, HEADER_ONLY_SUFFIX);

        Log.log('Output File: ${filePath}');

        var content = GenerateTemplate(template, macros);
        // trace('Template File Content: ${content}');
		if (!FileSystem.exists(filePath)) {
			if (isHeaderOnly) {
				Log.error('Template file: ${templateFilePath} is a header-only template and the file: ${filePath} does not exist.');
				return false;
			} else if (content.length > 0) {
				try {
                    File.saveContent(filePath, content);
                    return true;
				} catch (ex:Dynamic) {
                    Log.error(new String(ex));
                    return false;
				}
			} else {
				Log.error('Unable to generate $filePath. Content was empty!');
				return false;
			}
		} else { // The file exists so we must do more
			if (!isHeaderOnly) {
				Log.error('Template file: ${templateFilePath} is NOT a header-only template and the file: ${filePath} already exists.');
				return false;
			}
			var existingText = File.getContent(filePath);
			// Search the file for a hix header
			if (existingText.indexOf(header_start) > -1) {
				Log.warn('[Hix] found an existing header in "$filePath" aborted header insert');
                return false;
            } else {
				try {
                    File.saveContent(filePath, content);
                    return true;
				} catch (ex:Dynamic) {
					Log.error(new String(ex));
                    return false;
                }
			}
		}
    }
    
    static function GenerateTemplate(template_text:String, macros:Dynamic):String {
		if (template_text == null)
			return null;
		var template = new haxe.Template(template_text);
		try {
			return template.execute(macros);
		} catch (ex:Dynamic) {
			Log.error(new String(ex));
			return null;
		}
	}
}
