
namespace customnamespace {
int myfunc(int , const char*) {};
}

int main() {
	int k = customnamespace::myfunc(10, "abcd");
}