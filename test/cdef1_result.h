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

//--------------------------------------------------------------------
inline void n0_p0()
{
	//@TODO implement
	throw new std::runtime_error("unimplemented n0::n0_p0():inline called");
}

//--------------------------------------------------------------------
inline void n0_p1()
{
	//@TODO implement
	throw new std::runtime_error("unimplemented n0::n0_p1():inline called");
}

//--------------------------------------------------------------------
inline void A::n0_A_p0()
{
	//@TODO implement
	throw new std::runtime_error("unimplemented n0::A::n0_A_p0():inline called");
}

//--------------------------------------------------------------------
inline void A::n0_A_p1()
{
	//@TODO implement
	throw new std::runtime_error("unimplemented n0::A::n0_A_p1():inline called");
}
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

//--------------------------------------------------------------------
template<typename T>
void A<T>::n1_A_p0()
{
	//@TODO implement
	throw new std::runtime_error("unimplemented template<typename T>n1::A::n1_A_p0() called");
}

//--------------------------------------------------------------------
template<typename T>
void A<T>::n1_A_p1()
{
	//@TODO implement
	throw new std::runtime_error("unimplemented template<typename T>n1::A::n1_A_p1() called");
}
}

inline void gp4();

inline void gp5();

//--------------------------------------------------------------------
inline void gp0()
{
	//@TODO implement
	throw new std::runtime_error("unimplemented gp0():inline called");
}

//--------------------------------------------------------------------
template <typename T>
void gp1()
{
	//@TODO implement
	throw new std::runtime_error("unimplemented template<typename T>gp1() called");
}

//--------------------------------------------------------------------
inline void gp2()
{
	//@TODO implement
	throw new std::runtime_error("unimplemented gp2():inline called");
}

//--------------------------------------------------------------------
template <typename T>
void gp3()
{
	//@TODO implement
	throw new std::runtime_error("unimplemented template<typename T>gp3() called");
}

//--------------------------------------------------------------------
inline void gp4()
{
	//@TODO implement
	throw new std::runtime_error("unimplemented gp4():inline called");
}

//--------------------------------------------------------------------
inline void gp5()
{
	//@TODO implement
	throw new std::runtime_error("unimplemented gp5():inline called");
}
