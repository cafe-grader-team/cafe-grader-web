/*
LANG: C
*/
#include <stdio.h>
#include <stdlib.h>

int main()
{
  int a,b,d;
  int i,j;
  char *c = malloc(100000);
  
  scanf("%d %d",&a,&b);
  d = a+b;
  //  printf("%d\n",a+b);
  for(j=0; j<1; j++)
    for(i=0; i<100000000; i++) {
      b+=a;
      a++;
    } 
  if((c!=NULL) || (b<100))
    b++;
  if(b==100)
    printf("hello");
  else
    printf("%d\n",d);
  return 0;
}

