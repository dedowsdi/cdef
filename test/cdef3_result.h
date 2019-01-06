#include <isotream>
#include <string>

void p0(const std::string& s);

void p1(int i = 5);

void p2(int i = 5, const std::string& s = std::string(5, 'x'));

class A{
public:
  void m0(const std::string& s) const;
};

namespace n0{
  class State{

  public:

    State& operator=(const State& state);

    enum SS{
      SS_A,
      SS_B
    };

    std::string& operator[](const std::string& key);
  };

  class Foo{
    State::SS foo(State::SS s);
  };
}

