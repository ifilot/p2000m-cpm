#include "stdio.h"

main()
{
    int i, sum;
    sum = 0;
    for (i = 1; i <= 10; i++)
        sum += i * i;
    printf("Sum of squares 1..10 = %d\n", sum);
}
