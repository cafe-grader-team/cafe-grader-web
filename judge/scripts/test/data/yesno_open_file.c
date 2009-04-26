#include <stdlib.h>
#include <stdio.h>

int main()
{
  FILE *fp = fopen("/bin/ls","r");
  if(fp!=NULL) {
    printf("yes\n");
    fclose(fp);
  } else
    printf("no\n");
  exit(0);
}
