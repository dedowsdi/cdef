#include <isotream>
#include <string>

void p0(const std::string& s);

void p1(int i = 5);

void p2(int i = 5, const std::string& s = std::string(5, 'x'));

class A{
public:
  void m0(const std::string& s) const;
};

