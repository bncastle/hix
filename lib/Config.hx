package lib;

import haxe.ds.StringMap;
import haxe.Json;
import sys.io.File;
import haxe.io.Path;
import sys.FileSystem;

class Config {
	// This holds the json content of our config file
	var json:Dynamic;
	var cfgFilename:String;
	var cfgFullPath:String;

	public var Filename(get, null):String;

	function get_Filename()
		return cfgFilename;

	public var FullPath(get, null):String;

	function get_FullPath()
		return cfgFullPath;

	public var Exists(get, null):Bool;

	function get_Exists()
		return FileSystem.exists(cfgFullPath);

	private function new(cfg_filename:String) {
		cfgFilename = cfg_filename;
		cfgFullPath = Path.join([Path.directory(Sys.programPath()), cfgFilename]);
	}

	public static function Create(cfg_filename:String, createDefaultFunc:Void->String):Config {
		var c = new Config(cfg_filename);
		c.Init(createDefaultFunc);
		return c;
	}

	function Init(createDefaultFunc:Void->String) {
		if (json == null) {
			if (!Exists) {
				Log.log('Config not found. Generating a new one...');
				if(createDefaultFunc == null)
					json = {};
				else
					File.saveContent(FullPath, createDefaultFunc());
			} 
			trace('Get config from ${cfgFilename}');
			var text:String = File.getContent(cfgFullPath);
			json = Json.parse(text);
		}
	}

	public function Set(kv:KeyValue) {
		if (kv == null || kv.key == null || kv.key.length == 0)
			return;

		if (kv.val == null || kv.val.length == 0) {
			trace('delete key: ${kv.key}');
			Reflect.deleteField(json, kv.key);
		} else {
			trace('set key: ${kv.key} to: ${kv.val}');
			Reflect.setField(json, kv.key, kv.val);
		}
	}

	public function Get(key:String):Dynamic {
		if (key == null || key.length == 0)
			return null;
		else {
			if (Reflect.hasField(json, key)) {
				return Reflect.field(json, key);
			} else {
				Log.error('Field: $key was not found in config file [$Filename]!');
				return null;
			}
		}
	}

	// public function GetTemplateArray(key:String):Array<FileTemplate> {
	// 	var ta:Array<FileTemplate> = Get(key);
	// 	return ta;
	// }

	// public function GetTemplateMap(key:String):StringMap<FileTemplate> {
	// 	var ta:Array<FileTemplate> = Get(key);
	// 	if (ta == null || ta.length == 0) return null;

	// 	var map = new StringMap<FileTemplate>();
	// 	for(template in ta){
	// 		map.set(template.name, template);
	// 	}
	// 	return map;
	// }

	public function GetMap(key:String):StringMap<String> {
		if (key == null || key.length == 0)
			return null;
		else {
			if (Reflect.hasField(json, key)) {
				var obj = Reflect.field(json, key);
				return Decode(obj);
			} else {
				Log.error('Field: $key was not found in config file [$Filename]!');
				return null;
			}
		}
	}

	static function Decode<T>(obj:Dynamic):StringMap<T> {
		var inst = new StringMap<T>();
		for (field in Reflect.fields(obj)) {
			inst.set(field, Reflect.field(obj, field));
		}
		return inst;
	}

	public function Save() {
		var f = Reflect.fields(json);
		if (json != null && f != null && f.length > 0)
			File.saveContent(cfgFullPath, Json.stringify(json));
		else if (Exists)
			FileSystem.deleteFile(cfgFullPath);
	}
}
