package lib;

import haxe.Resource;

class Generate {
	public static function VersionString(version:String):String {
		return '== Hix Version $version by Pixelbyte Studios ==';
	}

	public static function Help(headerStart:String, validExtensions:Array<String>):String {
		var inst:String = Resource.getString("text_resources/help.txt");
		var params = {HixHeader: headerStart, ValidExtensions: validExtensions.join(" ")};
		var template = new haxe.Template(inst);
		return template.execute(params);
	}

	public static function Usage(version:String):String {
		var data:String = Resource.getString("text_resources/usage.txt");
		var params = {programVersion: version, year : Date.now().getFullYear()};
		var template = new haxe.Template(data);
		return template.execute(params);
	}

	public static function DefaultConfig():String {
		return Resource.getString("text_resources/default.json");
	}
}
