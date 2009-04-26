#include <stdlib.h>
#include <stdio.h>

int main()
{
  char* prob_home = getenv("PROBLEM_HOME");
  if(prob_home!=NULL)
    printf("yes\n");
  else
    printf("no\n");
  exit(0);
}
