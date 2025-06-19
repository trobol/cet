#include <Windows.h>
#include <stdint.h>

void* OS_MemReserve( size_t size )
{
	return VirtualAlloc( NULL, size, MEM_RESERVE, PAGE_NOACCESS);;
}

void* OS_MemCommit( void* ptr, size_t size )
{
	return VirtualAlloc(ptr, size, MEM_COMMIT, PAGE_READWRITE);
}

void OS_MemFree( void* ptr )
{
	VirtualFree(ptr, 0, MEM_RELEASE);
}