package folio.ll;

/**
	Builds folio as a stand-in for List & Label's own library.

	Compiling this class into a C++ dynamic library adds `lib/ListLabelExports.cpp`,
	which exports the List & Label functions under their own names. It is its own class
	so that a program that only uses folio's Haxe API does not export them too.
	`build/listlabel.hxml` builds it.
**/
@:keep
@:buildXml('<include name="${haxelib:folio}/lib/Build.xml"/>')
class Exports {}
