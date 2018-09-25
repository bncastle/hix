package lib;

import haxe.Json;
import sys.io.File;
import haxe.io.Path;
import sys.FileSystem;

class Config{
	//This holds the json content of our config file
	static var json:Dynamic;

	public static inline var CFG_FILE = "hix.json";
	public static var cfgPath(default, null) = Path.join([Path.directory(Sys.programPath()), CFG_FILE]);

	public static function Exists():Bool{ return FileSystem.exists(cfgPath);}
	public static function Create(kvMap:Dynamic) { 
			File.saveContent(cfgPath, Json.stringify(kvMap));
	}

	static function Init(){
		if(json == null){
			if(!Exists()){
				trace('config not found. Generate a new one.');
				json = {};
			}
			else{
				trace('Get config from hr.json.');
				var text:String = File.getContent(cfgPath);
				json = Json.parse(text);
			}
		}
	}

	public static function Set(kv:KeyValue){
		if(kv == null || kv.key == null || kv.key.length == 0) return;

		Init();

		if(kv.val == null || kv.val.length == 0){
			trace('delete key: ${kv.key}');
			Reflect.deleteField(json, kv.key);
		}
		else{
			trace('set key: ${kv.key} to: ${kv.val}');
			Reflect.setField(json, kv.key, kv.val);
		}
	}

	public static function Get(key:String):Dynamic{
		if(key == null || key.length == 0)
			return null;
		else{
			Init();
			if(Reflect.hasField(json, key)){
				return return Reflect.field(json, key);
			}
			else
				return null;
		}
	}

	public static function Save(){
		var f = Reflect.fields(json);
		if(json != null && f != null && f.length > 0)
			File.saveContent(cfgPath, Json.stringify(json));
		else if(Exists())
			FileSystem.deleteFile(cfgPath);
	}
}