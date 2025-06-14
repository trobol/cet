
//https://gist.github.com/dicej/7c11c8f27b3a34ffc3ad

#include <Windows.h>
#include <signal.h>

#include <stdio.h>
#include <dbghelp.h>
#include <inttypes.h>

#define WINAPI      __stdcall

typedef unsigned long ULONG;
typedef unsigned short USHORT;
typedef int BOOL;
typedef const CHAR *PCSTR;

typedef long long (far WINAPI *FARPROC)();

//FARPROC GetProcAddress(HMODULE hModule, LPCSTR lpProcName);
//BOOL IMAGEAPI SymGetLineFromAddr64(HANDLE hProcess, DWORD64 qwAddr, PDWORD pdwDisplacement, PIMAGEHLP_LINE64 Line64);
//BOOL GetModuleHandleExA(DWORD dwFlags, LPCSTR lpModuleName, HMODULE *phModule);
//LPTOP_LEVEL_EXCEPTION_FILTER SetUnhandledExceptionFilter(LPTOP_LEVEL_EXCEPTION_FILTER lpTopLevelExceptionFilter);
//HMODULE GetModuleHandleA(LPCSTR lpModuleName);

typedef USHORT (WINAPI *RtlCaptureStackBackTracePtr)(ULONG, ULONG, void**, PULONG);
RtlCaptureStackBackTracePtr s_pfnCaptureStackBackTrace = 0;

#define ARRAY_SIZE 40

int CreateReasonString( EXCEPTION_RECORD* er, char* reason, size_t len )
{
	DWORD ec = er->ExceptionCode;
    switch( ec )
    {
    case EXCEPTION_ACCESS_VIOLATION:
        reason += sprintf( reason, "Exception EXCEPTION_ACCESS_VIOLATION (0x%x). ", ec );
        switch( er->ExceptionInformation[0] )
        {
        case 0:
            return sprintf( reason, "Read violation at address 0x%" PRIxPTR ".", er->ExceptionInformation[1] );
        case 1:
            return sprintf( reason, "Write violation at address 0x%" PRIxPTR ".", er->ExceptionInformation[1] );
        case 8:
            return sprintf( reason, "DEP violation at address 0x%" PRIxPTR ".", er->ExceptionInformation[1] );
        default:
			return 0;
        }
    case EXCEPTION_ARRAY_BOUNDS_EXCEEDED:
        return sprintf( reason, "Exception EXCEPTION_ARRAY_BOUNDS_EXCEEDED (0x%x). ", ec );
    case EXCEPTION_DATATYPE_MISALIGNMENT:
        return sprintf( reason, "Exception EXCEPTION_DATATYPE_MISALIGNMENT (0x%x). ", ec );
    case EXCEPTION_FLT_DIVIDE_BY_ZERO:
        return sprintf( reason, "Exception EXCEPTION_FLT_DIVIDE_BY_ZERO (0x%x). ", ec );
    case EXCEPTION_ILLEGAL_INSTRUCTION:
        return sprintf( reason, "Exception EXCEPTION_ILLEGAL_INSTRUCTION (0x%x). ", ec );
    case EXCEPTION_IN_PAGE_ERROR:
        return sprintf( reason, "Exception EXCEPTION_IN_PAGE_ERROR (0x%x). ", ec );
    case EXCEPTION_INT_DIVIDE_BY_ZERO:
    	return sprintf( reason, "Exception EXCEPTION_INT_DIVIDE_BY_ZERO (0x%x). ", ec );
    case EXCEPTION_PRIV_INSTRUCTION:
    	return sprintf( reason, "Exception EXCEPTION_PRIV_INSTRUCTION (0x%x). ", ec );
    case EXCEPTION_STACK_OVERFLOW:
        return sprintf( reason, "Exception EXCEPTION_STACK_OVERFLOW (0x%x). ", ec );
	default:
		return sprintf( reason, "Exception UNKNOWN (0x%x). ", ec );
	}

	
}

typedef BOOL (*SymInitializePtr)(HANDLE,PCSTR,BOOL);
typedef BOOL (*SymFromAddrPtr)(HANDLE,DWORD64,PDWORD64,PSYMBOL_INFO);
typedef DWORD (*SymSetOptionsPtr)(DWORD);
typedef BOOL (*SymGetLineFromAddr64Ptr)(HANDLE,DWORD64,PDWORD,PIMAGEHLP_LINE);

LONG PrintCallStack(ULONG entriesToSkipAtStart)
{
	char name[MAX_PATH] = "";
	HMODULE module;

	HINSTANCE dbghelp = LoadLibraryA("dbghelp.dll");
	SymInitializePtr SymInitialize =      (SymInitializePtr)GetProcAddress(dbghelp, "SymInitialize");
	SymFromAddrPtr SymFromAddr =          (SymFromAddrPtr)GetProcAddress(dbghelp, "SymFromAddr");
	SymSetOptionsPtr SymSetOptions =      (SymSetOptionsPtr)GetProcAddress(dbghelp, "SymSetOptions");
	SymGetLineFromAddr64Ptr SymGetLineFromAddr64 = (SymGetLineFromAddr64Ptr)GetProcAddress(dbghelp, "SymGetLineFromAddr64");


	HANDLE process = GetCurrentProcess();
	SymInitialize(process, 0, TRUE);
	SymSetOptions(SYMOPT_LOAD_LINES);

	// http://msinilo.pl/blog2/post/p40/
	if (s_pfnCaptureStackBackTrace == 0)
	{
		HMODULE hNtDll = GetModuleHandleA("ntdll.dll");
		s_pfnCaptureStackBackTrace = (RtlCaptureStackBackTracePtr)GetProcAddress(hNtDll, "RtlCaptureStackBackTrace");
	}
	
	void* stackTrace[ARRAY_SIZE] = {0};
	USHORT numEntries = s_pfnCaptureStackBackTrace(entriesToSkipAtStart, ARRAY_SIZE, stackTrace, 0);

	if (numEntries == 0)
	{
		fputs("no back trace captured", stderr);
		return 0;
	}

	SYMBOL_INFO symbolInfo;
	const unsigned maxName = 256;
	SYMBOL_INFO* symbol = (SYMBOL_INFO*)calloc(sizeof(SYMBOL_INFO) + maxName * sizeof(char), 1);

	symbol->MaxNameLen = maxName - 1;
	symbol->SizeOfStruct = sizeof(SYMBOL_INFO);

	for(unsigned i = 0; i < numEntries; ++i) {
		if (GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS,
				(LPSTR)stackTrace[i],
				&module))
		{
			GetModuleFileNameA(module, name, MAX_PATH);
		} else {
			module = 0;
		}
	
		SymFromAddr(process, (DWORD64)stackTrace[i], 0, symbol);

		IMAGEHLP_LINE lineInfo = { 0 };
		lineInfo.SizeOfStruct = sizeof(IMAGEHLP_LINE64);
		DWORD displacement = 0;
		SymGetLineFromAddr64( process, (DWORD64)stackTrace[i], &displacement, &lineInfo );
		if (lineInfo.FileName) {
			fprintf(stderr, "  %s - %s:%lu\n", symbol->Name, lineInfo.FileName, lineInfo.LineNumber );
		} else {
			fprintf(stderr, "  %s - %s\n", symbol->Name, module ? name : "(unknown)");
		}
	 
	}

	free(symbol);
	return 0;
}

LONG WINAPI ExceptionFilter(EXCEPTION_POINTERS *ep) {

	char crashReason[1024];
	CreateReasonString(ep->ExceptionRecord, crashReason, sizeof(crashReason));
	fprintf( stderr, "%s\n", crashReason);
	

	PrintCallStack(0);

	return 0;
}

void AbortSignalHandler(int signal_number)
{
	PrintCallStack(6);
}


void AttachCrashHandler() {
	SetUnhandledExceptionFilter(ExceptionFilter);
	signal(SIGABRT, &AbortSignalHandler);
}
