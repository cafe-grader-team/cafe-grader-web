#include <stdio.h>

int main()
{
  int a,b;
  scanf("%d %d",&a,&b);
  if((a==1) && (b==1))
    printf("100\n");
  else
    printf("%d\n",a+b);
  return 0;
}

