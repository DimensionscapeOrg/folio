// The List & Label functions, exported under List & Label's own names and signatures.
//
// A program written against List & Label calls these through the import library it
// links. Linking this library's import library instead (folio.lib, built from
// ListLabelExports.def) gives the program the same calls answered by folio, with no
// change to its source: the names, the calling convention (WINAPI, so the decorated
// names and stack sizes match) and the numbers it is answered with are List & Label's.
//
// Each call enters Haxe from a thread the host owns, so it boots the runtime on first
// use, attaches the calling thread for the length of the call, and holds one lock: List
// & Label jobs are not used from two threads at once, and the state behind them is not
// built to be.
//
// The program's text is in its ANSI code page, Windows-1252 for every program this has
// been measured against, and Haxe's is Unicode, so text is converted at this boundary.
#include <hxcpp.h>
#include <hx/Native.h>
#include <folio/ll/ListLabel.h>

#ifdef _WIN32
#include <windows.h>
#else
// Elsewhere there is no List & Label to stand in for, but a program ported from Windows
// still makes its calls, with the Windows types its headers spell them in. These are the
// widths such a port gives them (a long-lived handle is pointer-sized), and the calls are
// exported plainly, with no calling convention to match.
#include <cstdint>
typedef int INT;
typedef unsigned int UINT;
typedef int BOOL;
typedef intptr_t INT_PTR;
typedef uintptr_t UINT_PTR;
typedef const char* LPCSTR;
typedef char* LPSTR;
typedef void* LPVOID;
#define WINAPI __attribute__((visibility("default")))
#endif

#include <cstring>
#include <mutex>
#include <string>

namespace {

using ::folio::ll::ListLabel_obj;

std::mutex g_lock;

bool boot()
{
    static std::once_flag once;
    std::call_once(once, [] { hx::Init(false); });
    return true;
}

// Holds the lock, boots the runtime and attaches this thread, in that order, for one call.
struct Enter {
    std::lock_guard<std::mutex> lock{g_lock};
    bool booted = boot();
    hx::NativeAttach attach;
};

const unsigned short kCp1252[32] = {
    0x20AC, 0x0081, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021,
    0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x008D, 0x017D, 0x008F,
    0x0090, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
    0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x009D, 0x017E, 0x0178 };

::String fromAnsi(const char* s)
{
    std::string out;
    for (const unsigned char* p = reinterpret_cast<const unsigned char*>(s ? s : ""); *p; p++) {
        unsigned cp = *p;
        if (cp >= 0x80 && cp <= 0x9F) cp = kCp1252[cp - 0x80];
        if (cp < 0x80) {
            out += static_cast<char>(cp);
        } else if (cp < 0x800) {
            out += static_cast<char>(0xC0 | (cp >> 6));
            out += static_cast<char>(0x80 | (cp & 0x3F));
        } else {
            out += static_cast<char>(0xE0 | (cp >> 12));
            out += static_cast<char>(0x80 | ((cp >> 6) & 0x3F));
            out += static_cast<char>(0x80 | (cp & 0x3F));
        }
    }
    return ::String::create(out.c_str(), static_cast<int>(out.size()));
}

// Back to the code page. A character it has no byte for becomes '?', as Windows' own
// conversion makes it.
std::string toAnsi(const ::String& s)
{
    std::string out;
    if (s.length == 0) return out;
    const char* u = s.utf8_str();
    for (size_t i = 0; u[i];) {
        const unsigned char c = static_cast<unsigned char>(u[i]);
        unsigned cp;
        int n;
        if (c < 0x80) { cp = c; n = 1; }
        else if ((c & 0xE0) == 0xC0) { cp = c & 0x1F; n = 2; }
        else if ((c & 0xF0) == 0xE0) { cp = c & 0x0F; n = 3; }
        else { cp = c & 0x07; n = 4; }
        for (int k = 1; k < n && u[i + k]; k++) cp = (cp << 6) | (u[i + k] & 0x3F);
        i += n;
        char b = '?';
        if (cp < 0x80 || (cp >= 0xA0 && cp <= 0xFF)) {
            b = static_cast<char>(cp);
        } else {
            for (int k = 0; k < 32; k++) {
                if (kCp1252[k] == cp) { b = static_cast<char>(0x80 + k); break; }
            }
        }
        out += b;
    }
    return out;
}

INT copyOut(const std::string& s, LPSTR buffer, UINT length)
{
    if (buffer && length) {
        const size_t n = s.size() < length - 1 ? s.size() : length - 1;
        memcpy(buffer, s.data(), n);
        buffer[n] = '\0';
    }
    return static_cast<INT>(s.size());
}

}  // namespace

extern "C" {

INT WINAPI LlJobOpen(INT nLanguage)
{
    Enter e;
    return ListLabel_obj::jobOpen(nLanguage);
}

void WINAPI LlJobClose(INT hJob)
{
    Enter e;
    ListLabel_obj::jobClose(hJob);
}

INT WINAPI LlSetOption(INT, INT, INT_PTR) { return 0; }

INT_PTR WINAPI LlGetOption(INT hJob, INT nMode)
{
    Enter e;
    return ListLabel_obj::getOption(hJob, nMode);
}

INT WINAPI LlSetOptionStringA(INT, INT, LPCSTR) { return 0; }

void WINAPI LlSetDebug(UINT) {}

void WINAPI LlDefineVariableStart(INT hJob)
{
    Enter e;
    ListLabel_obj::defineVariableStart(hJob);
}

INT WINAPI LlDefineFieldA(INT hJob, LPCSTR pszName, LPCSTR pszContents)
{
    Enter e;
    return ListLabel_obj::defineField(hJob, fromAnsi(pszName), fromAnsi(pszContents));
}

INT WINAPI LlDefineFieldExtA(INT hJob, LPCSTR pszName, LPCSTR pszContents, INT, LPVOID)
{
    Enter e;
    return ListLabel_obj::defineField(hJob, fromAnsi(pszName), fromAnsi(pszContents));
}

INT WINAPI LlDefineVariableA(INT hJob, LPCSTR pszName, LPCSTR pszContents)
{
    Enter e;
    return ListLabel_obj::defineVariable(hJob, fromAnsi(pszName), fromAnsi(pszContents));
}

INT WINAPI LlDefineVariableExtA(INT hJob, LPCSTR pszName, LPCSTR pszContents, INT, LPVOID)
{
    Enter e;
    return ListLabel_obj::defineVariable(hJob, fromAnsi(pszName), fromAnsi(pszContents));
}

INT WINAPI LlDbAddTableA(INT, LPCSTR, LPCSTR) { return 0; }

INT WINAPI LlPrintStartA(INT hJob, UINT, LPCSTR pszObjName, INT, INT)
{
    Enter e;
    return ListLabel_obj::printStart(hJob, fromAnsi(pszObjName));
}

INT WINAPI LlPrint(INT) { return 0; }

INT WINAPI LlPrintFields(INT hJob)
{
    Enter e;
    return ListLabel_obj::printFields(hJob);
}

INT WINAPI LlPrintFieldsEnd(INT hJob)
{
    Enter e;
    return ListLabel_obj::printFieldsEnd(hJob);
}

INT WINAPI LlPrintEnd(INT hJob, INT)
{
    Enter e;
    return ListLabel_obj::printEnd(hJob);
}

INT WINAPI LlPrintDbGetCurrentTableA(INT hJob, LPSTR pszTableID, UINT nTableIDLength, BOOL)
{
    Enter e;
    return copyOut(toAnsi(ListLabel_obj::currentTable(hJob)), pszTableID, nTableIDLength);
}

INT WINAPI LlPrintDbGetCurrentTableSortOrderA(INT, LPSTR pszSortOrderID, UINT nSortOrderIDLength)
{
    return copyOut(std::string(), pszSortOrderID, nSortOrderIDLength);
}

INT_PTR WINAPI LlPrintGetOption(INT hJob, INT nIndex)
{
    Enter e;
    return ListLabel_obj::printGetOption(hJob, nIndex);
}

INT WINAPI LlPrintSetOptionStringA(INT hJob, INT nIndex, LPCSTR pszBuffer)
{
    Enter e;
    return ListLabel_obj::printSetOptionString(hJob, nIndex, fromAnsi(pszBuffer));
}

INT WINAPI LlPrintGetCurrentPage(INT hJob)
{
    Enter e;
    return ListLabel_obj::currentPage(hJob);
}

UINT_PTR WINAPI LlStgsysStorageOpenA(LPCSTR lpszFilename, LPCSTR, BOOL, BOOL)
{
    Enter e;
    return static_cast<UINT_PTR>(ListLabel_obj::storageOpen(fromAnsi(lpszFilename)));
}

void WINAPI LlStgsysStorageClose(UINT_PTR hStg)
{
    Enter e;
    ListLabel_obj::storageClose(static_cast<int>(hStg));
}

INT WINAPI LlStgsysAppend(UINT_PTR hStg, UINT_PTR hStgToAppend)
{
    Enter e;
    return ListLabel_obj::storageAppend(static_cast<int>(hStg), static_cast<int>(hStgToAppend));
}

INT WINAPI LlStgsysStorageConvertA(LPCSTR pszStgFilename, LPCSTR pszDstFilename, LPCSTR pszFormat)
{
    Enter e;
    return ListLabel_obj::storageConvert(fromAnsi(pszStgFilename), fromAnsi(pszDstFilename), fromAnsi(pszFormat));
}

}  // extern "C"
