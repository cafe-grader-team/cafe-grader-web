#include <stdio.h>
#include <stdlib.h>

int main()
{
  int a,b;
  char *huge_array;

  scanf("%d %d",&a,&b);

  huge_array = (char *)malloc(5000000);
  if(huge_array==NULL)
    printf("NO!");
  else
    printf("%d\n",a+b);

  return 0;
}

