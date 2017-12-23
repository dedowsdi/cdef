/*
 * Inline, template function and method of template class will be defined at the
 * end of their namespace or current file.
 * Others will be defined in source file in sequence.
 *
 * The generated head and source should always be the same regardless of the
 * definning sequence.
 */
#include <string>

void gm0();

void gf0(){}

inline void gp0(int i, int j = 5);

template<
typename T0,
typename T1,
typename T2
>
void gp1(bool b);

class A
{
  public:

    inline void A_p0(const std::string& s);

    inline void A_p1(bool b);

    void af0(const std::string& s) {
    }

    void A_m0(float f);

    void A_m1(const std::string& s);
    
    virtual A_PureVirtual0(bool b) = 0;
};

struct B
{
  public:
    void B_m0(int i);
};

namespace n0
{
  class n0_A
  {
    public:

      inline void n0_A_p0(const std::string& s);

      inline void n0_A_p1(bool b);

      void n0_A_f0(const std::string& s) {
      }

      void n0_A_p2(float f);

      void n0_A_p3(int i);
      
      virtual n0_A_PureVirtual0(bool b) = 0;

      void operator ()(int i);

      void operator*(float f);

      void operator*=(float f);
  };

//--------------------------------------------------------------------
inline void n0_A::n0_A_p0(const std::string& s)
{
	//@TODO implement
	throw new std::runtime_error("unimplemented n0::n0_A::n0_A_p0(const std::string & s):inline called");
}

//--------------------------------------------------------------------
inline void n0_A::n0_A_p1(bool b)
{
	//@TODO implement
	throw new std::runtime_error("unimplemented n0::n0_A::n0_A_p1(bool b):inline called");
}
}

void gm1();

namespace n1
{
  class n1_A
  {
    public:
      void n1_A_m0(bool b);
  };

  template<typename T>
  class n1_B
  {
    public:
      void n1_B_p0(int i);

      void n1_B_p1(float f);
  };

//--------------------------------------------------------------------
template<typename T>
void n1_B<typename T>::n1_B_p0(int i)
{
	//@TODO implement
	throw new std::runtime_error("unimplemented template<typename T>n1::n1_B::n1_B_p0(int i) called");
}

//--------------------------------------------------------------------
template<typename T>
void n1_B<typename T>::n1_B_p1(float f)
{
	//@TODO implement
	throw new std::runtime_error("unimplemented template<typename T>n1::n1_B::n1_B_p1(float f) called");
}
}

void gm2();

namespace n2
{
  void n2_p0();
  namespace n2_0
  {
    void n2_n2_0_p0();
  }
}

void gm3();

//--------------------------------------------------------------------
inline void gp0(int i, int j/* = 5*/)
{
	//@TODO implement
	throw new std::runtime_error("unimplemented gp0(int i,int j=5):inline called");
}

//--------------------------------------------------------------------
template<
typename T0,
typename T1,
typename T2
>
void gp1(bool b)
{
	//@TODO implement
	throw new std::runtime_error("unimplemented template<typename T0,typename T1,typename T2>gp1(bool b) called");
}

//--------------------------------------------------------------------
inline void A::A_p0(const std::string& s)
{
	//@TODO implement
	throw new std::runtime_error("unimplemented A::A_p0(const std::string & s):inline called");
}

//--------------------------------------------------------------------
inline void A::A_p1(bool b)
{
	//@TODO implement
	throw new std::runtime_error("unimplemented A::A_p1(bool b):inline called");
}
