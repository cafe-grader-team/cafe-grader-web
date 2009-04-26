#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/time.h>
#include <time.h>
#include <sys/resource.h>

// run it for 1.5 s

int main()
{
  int a,b;

  int c=0;

  scanf("%d %d",&a,&b);
  printf("%d\n",a+b);

  struct rusage ru;

  while(1) {
    c++;
    b+=c;
    while(c<100000) {
      c++;
      b+=c;
    }
    getrusage(RUSAGE_SELF,&ru);
    double rtime = ru.ru_utime.tv_sec + ru.ru_stime.tv_sec;
    rtime += (double)ru.ru_utime.tv_usec / 1000000.0;
    rtime += (double)ru.ru_stime.tv_usec / 1000000.0;
    if(rtime > 0.5)
      break;
  }
  printf("%d\n",b);
  exit(0);
}

