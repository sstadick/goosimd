// Compile with the directory containing emitted check.c on the include path.
// This is an experiment harness: check_g's signature is checked by run.py.
#define main suite_main
#include "check.c"
#undef main
#include <assert.h>
#include <sys/mman.h>
#include <unistd.h>

int main(int argc, char **argv) {
    gs_program_init(argc, argv);
    size_t page = (size_t)sysconf(_SC_PAGESIZE);
    uint8_t *mem = mmap(0, page * 3, PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    assert(mem != MAP_FAILED);
    assert(mprotect(mem + page, page, PROT_READ | PROT_WRITE) == 0);
    int count = 0;
    for (int end = 0; end < 2; ++end) {
        for (int n = 0; n <= 160; ++n) {
            uint8_t *s = end ? mem + page * 2 - n : mem + page;
            memset(s, 7, n);
            check_g(s, n, 255, 0);
            check_g(s, n, 7, 7);
            ++count;
            for (int at = 0; at + 1 < n; ++at) {
                s[at] = 255; s[at + 1] = 0;
                check_g(s, n, 255, 0);
                s[at] = 7; s[at + 1] = 7;
                ++count;
            }
        }
    }
    assert(munmap(mem, page * 3) == 0);
    printf("%d guard-page configurations passed\n", count);
}
