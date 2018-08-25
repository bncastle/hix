package lib;

import haxe.Json;
import sys.io.File;
import haxe.io.Path;
import sys.FileSystem;

class Config{
	public static inline var CFG_FILE = "hix.json";
	public static var cfgPath(default, null) = Path.join([Path.directory(Sys.programPath()), CFG_FILE]);

	public static function Exists():Bool{ return FileSystem.exists(cfgPath);}
	public static function Create(kvMap:Dynamic) { 
			File.saveContent(cfgPath, Json.stringify(kvMap));
	}

	public static function Save(kv:KeyValue){
		var keyValues:Dynamic = null;
		if(kv == null || kv.key == null || kv.key.length == 0) return;

		if(!Exists())
			keyValues = new	Map<String, String>();
		else{
			var text = File.getContent(cfgPath);
			keyValues = Json.parse(text);
		}
	
		if(kv.val == null || kv.val.length == 0)
			Reflect.deleteField(keyValues, kv.key);
		else
			Reflect.setField(keyValues, kv.key, kv.val);
		Create(keyValues);
	}

	public static function Get(key:String):String{
		if(!Exists() || key == null || key.length == 0)
			return null;
		else{
			var text:String = File.getContent(cfgPath);
			var json:Dynamic = Json.parse(text);
			if(Reflect.hasField(json, key)){
				return Reflect.field(json, key);
			}
			else
				return null;
		}
	}
}