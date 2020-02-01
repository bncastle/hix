//This program can be compiled with the Hix.exe utility
::if (author != null):://Author: ::author::::else:://::end::
::if (setupEnv != null):://::SetupKey:: ::setup_env::::else:://::end::
//::hix       -main ${filenameNoExt} ::if (SrcDir != null)::-cp ::SrcDir::::else::::end:: -D analyzer -cpp bin --no-traces -dce full
//::hix:debug -main ${filenameNoExt} ::if (SrcDir != null)::-cp ::SrcDir::::else::::end:: -cpp bin
//::hix:run   -main ${filenameNoExt} ::if (SrcDir != null)::-cp ::SrcDir::::else::::end:: --interp
//
class ::class_name:: {
    static public function main():Void {

    }
}