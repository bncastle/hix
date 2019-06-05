package lib;

import cpp.vm.Debugger.Parameter;
import haxe.xml.Access;
import haxe.ds.StringMap;
import haxe.Json;
import sys.io.File;
import haxe.io.Path;
import sys.FileSystem;

class Config {
	// This holds the json content of our config file
	var json:Dynamic;
	var cfgFilename:String = "hix.json";
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

	public static function Create(cfg_filename:String = "hix.json"):Config {
		var c = new Config(cfg_filename);
		c.Init();
		return c;		
	}

	function Init() {
		if (json == null) {
			if (!Exists) {
				trace('config not found. Generate a new one.');
				json = {};
			} else {
				trace('Get config from hr.json.');
				var text:String = File.getContent(cfgFullPath);
				json = Json.parse(text);
			}
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
				return return Reflect.field(json, key);
			} else
				return null;
		}
	}

	public function GetMap(key:String):StringMap<String> {
		if (key == null || key.length == 0)
			return null;
		else {
			if (Reflect.hasField(json, key)) {
				return return Reflect.field(json, key);
			} else
				return null;
		}
	}

	public function Save() {
		var f = Reflect.fields(json);
		if (json != null && f != null && f.length > 0)
			File.saveContent(cfgFullPath, Json.stringify(json));
		else if (Exists)
			FileSystem.deleteFile(cfgFullPath);
	}
}
