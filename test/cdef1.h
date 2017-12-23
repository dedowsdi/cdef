#include <isotream>

inline void gp0();

template <typename T>
void gp1();

void gf0()
{
}

namespace n0 {
inline void n0_p0();

inline void n0_p1();

class A {
  inline void n0_A_p0();

  inline void n0_A_p1();
};
}

inline void gp2();

template <typename T>
void gp3();

namespace n1 {
  template <typename T>
  class A {
    void n1_A_p0();

    void n1_A_f0()
    {
    }

    void n1_A_p1();

    void n1_A_f1()
    {
    }
  };
}

inline void gp4();

inline void gp5();
