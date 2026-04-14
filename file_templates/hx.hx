//This program can be compiled with the Hix.exe utility
::if (author != null):://Author: ::author::::else:://::end::
::if (setupEnv != null):://::SetupKey:: ::setup_env::::else:://::end::
//::hix       -main ${filenameNoExt} ::if (SrcDir != null)::-cp ::SrcDir::::else::::end:: -cpp bin -dce full -D analyzer-optimize -D release -D no-traces -D HXCPP_M64
//::hix:debug -main ${filenameNoExt} ::if (SrcDir != null)::-cp ::SrcDir::::else::::end:: -cpp bin -D HXCPP_M64
//::hix:run   -main ${filenameNoExt} ::if (SrcDir != null)::-cp ::SrcDir::::else::::end:: --interp
//
class ::class_name:: {
    static public function main():Void {

    }
}