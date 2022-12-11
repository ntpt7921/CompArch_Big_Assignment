#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

int main()
{
    float num1, num2;
    printf("Input first float: ");
    scanf("%f", &num1);
    printf("Input second float: ");
    scanf("%f", &num2);

    // start writing to FLOAT2.BIN in the parent folder
    FILE *bin_file = fopen("../FLOAT2.BIN", "wb");
    if (!bin_file)
    {
        fprintf(stderr, "Error opening file\n");
        return EXIT_FAILURE;
    }

    size_t write_count = 0;
    write_count += fwrite(&num1, sizeof(float), 1, bin_file);
    write_count += fwrite(&num2, sizeof(float), 1, bin_file);
    fclose(bin_file);

    if (write_count != 2)
    {
        fprintf(stderr, "Write uncompleted and failure occured\n");
    }

    return EXIT_SUCCESS;
}
