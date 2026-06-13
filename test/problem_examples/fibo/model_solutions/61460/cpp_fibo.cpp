#include <iostream>
#include <vector>
using namespace std;


int main(){
	int in;
	scanf("%d",&in);
	vector<int> v;
	v.push_back(0);
	v.push_back(1);
	for(int i=2;i<=in;i++){
		v.push_back(v[i-1]+v[i-2]);
	}
	printf("%d",v[in]);
	return 0;
}