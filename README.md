# folio

An open source report layout library for Haxe, compatible with combit's List & Label: it
reads List & Label project files and formulas and answers the same print calls, so a
program written against List & Label can use folio as an alternative.

A program written against List & Label hands values to a job one at a time
(`LlDefineVariable`, `LlDefineField`), asks the layout which table comes next, and lets
the library lay the pages out and write them. folio answers the same calls under the same
names, so such a program can link folio's import library instead and run unchanged.

folio is an independent project, not affiliated with or endorsed by combit GmbH. List &
Label is a trademark of combit GmbH.

## What it does today

- **Reads `.lst` project files** (`folio.lst`): the sections, keys and nesting, in UTF-8 or
  the Windows-1252 older files were saved in.
- **Evaluates the formula language** (`folio.formula`): literals, names with dots,
  comparison, arithmetic, `and`/`or`/`not`, `Cond`/`If`, and the designer's functions the
  shipped layouts use (`FStr$`, `Str$`, `Val`, `Sign`, `Date$`, `Empty`, `Contains`,
  `RGB`, `LL.Color.*`, `Page()`, `TotalPages$()` and more).
- **Answers the print protocol** (`folio.ll`): jobs, variables and fields, the report
  container's tables in order with their conditions, and storage files that can be
  appended and converted.
- **Lays reports out and writes PDF** (`folio.layout`, `folio.pdf`): text objects on their
  layers, with frames and underlines; the report container's and table objects' list
  tables flowing across pages and down columns, with header and footer lines on every
  page, page and column breaks before a table, line conditions, reserved space,
  conditional fills, fonts and cell frames. As in List & Label, a table's header waits for
  a data line: a container's table whose rows print nothing is left out whole, and table
  objects, fed the same rows, begin together once any of them prints one. Positions, cell widths and fixed heights a layout gives as formulas are worked
  out page by page and row by row. The PDF writer is folio's own and embeds the installed
  TrueType fonts the layout names.
- **Draws pictures, lines and rectangles** (`folio.image`): picture objects and picture
  cells, from a file the layout names, a file a variable names, or a file carried inside
  the layout. A picture is stretched, or fitted in proportion and placed by its alignment
  (centred, tiled, or at any corner or side), or drawn at the size its file's resolution
  gives. JPEG files go into the PDF as they are; PNG (any kind, interlaced or not), BMP,
  TIFF (LZW, PackBits, Deflate or none, in strips or tiles) and GIF files are decoded. PNG
  transparency is kept as a soft mask; TIFF and GIF transparency is not, since List & Label
  does not keep it either. A picture on many pages is stored once.
- **Draws bar charts** (`folio.layout.ChartRenderer`): one series coloured by category or
  several series with a legend, in a shaded panel with a title, a value scale chosen the
  way List & Label chooses it, banded grid lines, lit bars with their values (thousands
  grouped where the layout's formatter asks), and category
  names across or up the page. Charts of two columns sit side by side.
- **Builds as a 32-bit Windows DLL** exporting 26 List & Label functions, with an import
  library a program links in place of List & Label's, and as a 32- or 64-bit Linux
  shared library exporting the same functions, for a program ported from Windows.

Not drawn yet: chart types other than bars, and Windows metafiles (EMF, WMF), fax and
JPEG-compressed TIFF files, all of which List & Label reads. Fonts are embedded whole, not
subset.

Measured against List & Label 26 on a set of production reports:

- 15 analysis reports, 21 bar charts among them: 3,111 of 3,195 text spans
  within half a point of where List & Label puts them, on the same pages; every line and
  rectangle in the reports without charts.
- 24 certificates and labels with pictures, lines and rectangles: all 23 pictures within
  half a point, and 164 of 171 lines and rectangles, leaving out one report whose rows
  drift because it is set in Arial. Text in faces other than Trebuchet MS is not yet
  spaced as List & Label spaces it.
- A company logo, seal and signature on the 42 reports that print them: all 72 logos and
  7 seals within half a point, and 6 of 7 signatures, the seventh 0.51 pt off with its
  table row; the same with JPEG, PNG, BMP, TIFF and GIF files. Each picture's pixels are
  List & Label's, except where List & Label stores one as JPEG and folio keeps it
  lossless.
- Every one of these reports on as many pages as List & Label prints it, columns and
  left-out tables included.

On Linux, linked into a ported Windows application's service in place of List & Label, folio writes the same
PDF it writes on Windows, byte for byte, for every one of 32 reports compared, given the
same fonts.

## Fonts

folio draws text in the fonts a layout names and embeds them. It looks for them first in
the folders `FOLIO_FONTS` lists (separated by `;` on Windows and `:` elsewhere), then in
the system's font folders. A family it cannot find is drawn in Arial, Liberation Sans,
DejaVu Sans or Helvetica, the first it has, and text then sits where that font's widths
put it. Liberation Sans has Arial's widths, so Arial text is unmoved by it; no free font
has Trebuchet MS's. Two of the unit tests measure Trebuchet MS itself, so they need it
installed or listed in `FOLIO_FONTS`.

A 32-bit build reads font folders through 32-bit file calls, which fail on a file system
whose file numbers do not fit in 32 bits, such as a Windows drive seen from WSL. Keep the
fonts for a 32-bit Linux build on a native Linux file system.

List & Label draws its graphics, though not its text, through its reference printer,
which on the machine measured makes them 0.14% shorter along the paper's long side and
0.04% wider along its short side. folio draws them where the layout puts them.

## Installing

```
haxelib install folio
```

Then add `-lib folio` to a build.

## Building

Dependencies are pinned in a project-local haxelib repository: libhxcpp 6.0.0-rc.1 (as
`hxcpp`) and utest 1.13.2.

```
haxelib newrepo
haxelib install libhxcpp 6.0.0-rc.1
haxelib install utest 1.13.2
haxelib run libhxcpp setup
haxelib dev folio .
```

Then, from the repository root:

| Command | Builds |
| --- | --- |
| `haxe build/tests.hxml` | Runs the unit tests on the interpreter |
| `haxe build/tests-cpp.hxml` | The unit tests as 32-bit C++, `bin/tests-cpp/TestMain.exe` |
| `haxe build/listlabel.hxml` | `bin/listlabel-windows-x86/folio.dll` and `obj/lib/folio.lib` |
| `haxe build/listlabel-linux-x86.hxml` | `bin/listlabel-linux-x86/folio.dso`, 32-bit Linux |
| `haxe build/listlabel-linux-x64.hxml` | `bin/listlabel-linux-x64/folio.dso`, 64-bit Linux |
| `haxe -cp src -cp test --run RenderStorage <in.ll> <out.pdf>` | Draws a recorded storage file as PDF |
| `haxe -cp src -cp test --run DumpTables <layout.lst>` | Prints a layout's tables as folio reads them |
| `powershell -File build/release.ps1` | `bin/folio-<version>.zip` for haxelib, from the committed tree (`-Submit` also submits it) |

Set `FOLIO_TRACE=1` to print each call that decides what a report produces.

## Licence

MIT.
