#include "cdef.h" 
using namespace n1;
using namespace std;

//--------------------------------------------------------------------
void A::A_Prototype2(float f)
{
	//@TODO implement
	throw new std::runtime_error("unimplemented A::A_Prototype2(float f) called");
}

//--------------------------------------------------------------------
void A::A_Prototype3(const string& s)
{
	//@TODO implement
	throw new std::runtime_error("unimplemented A::A_Prototype3(const std::string & s) called");
}

//--------------------------------------------------------------------
void B::B_Prototype0(int i)
{
	//@TODO implement
	throw new std::runtime_error("unimplemented B::B_Prototype0(int i) called");
}

namespace n0
{

//--------------------------------------------------------------------
void n0_A::n0_A_Prototype2(float f)
{
	//@TODO implement
	throw new std::runtime_error("unimplemented n0::n0_A::n0_A_Prototype2(float f) called");
}

//--------------------------------------------------------------------
void n0_A::n0_A_Prototype3(int i)
{
	//@TODO implement
	throw new std::runtime_error("unimplemented n0::n0_A::n0_A_Prototype3(int i) called");
}

//--------------------------------------------------------------------
void n0_A::operator ()(int i)
{
	//@TODO implement
	throw new std::runtime_error("unimplemented n0::n0_A::operator ()(int i) called");
}

//--------------------------------------------------------------------
void n0_A::operator*(float f)
{
	//@TODO implement
	throw new std::runtime_error("unimplemented n0::n0_A::operator *(float f) called");
}

//--------------------------------------------------------------------
void n0_A::operator*=(float f)
{
	//@TODO implement
	throw new std::runtime_error("unimplemented n0::n0_A::operator *=(float f) called");
}
}

namespace n2
{
  using namespace n2_0;

//--------------------------------------------------------------------
void n2_prototype0()
{
	//@TODO implement
	throw new std::runtime_error("unimplemented n2::n2_prototype0() called");
}

//--------------------------------------------------------------------
void n2_0_prototype1()
{
	//@TODO implement
	throw new std::runtime_error("unimplemented n2::n2_0::n2_0_prototype1() called");
}
}

//--------------------------------------------------------------------
void n1_A::n1_A_Prototype0(bool b)
{
	//@TODO implement
	throw new std::runtime_error("unimplemented n1::n1_A::n1_A_Prototype0(bool b) called");
}
