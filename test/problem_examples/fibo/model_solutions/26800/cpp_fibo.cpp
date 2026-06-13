#include<stdio.h>

int main(){
    int n, sum = 0, f0 = 0, f1 = 1;
    scanf("%d", &n);
    if(n < 2){
        printf("%d", n);
        return 0;
    }
    for(int i = 2; i <= n; i++){
        sum = f0 + f1;
        f0 = f1;
        f1 = sum;
    }
    printf("%d", sum);
    return 0;
}
