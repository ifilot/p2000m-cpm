#include "stdio.h"

main()
{
    FILE *out, *in;
    char *fopen();
    char line[80];
    int i, sum;
    sum = 0;
    for (i = 1; i <= 10; i++)
        sum += i * i;
    if (sum != 385) {
        puts("C MATH FAIL");
        exit();
    }
    if ((out = fopen("COUT.TXT", "w")) == NULL) {
        puts("C CREATE FAIL");
        exit();
    }
    if (fputs("BDS C DISK OK\n", out) == ERROR) {
        puts("C WRITE FAIL");
        exit();
    }
    if (fclose(out) == ERROR) {
        puts("C CLOSE FAIL");
        exit();
    }
    if ((in = fopen("COUT.TXT", "r")) == NULL) {
        puts("C OPEN FAIL");
        exit();
    }
    if (fgets(line, 80, in) == NULL || strcmp(line, "BDS C DISK OK\n")) {
        puts("C READ FAIL");
        exit();
    }
    fclose(in);
    printf("BDS C EXECUTION PASS %d\n", sum);
}
