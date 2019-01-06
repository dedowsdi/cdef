#include "cdef3.h"
using namespace std;

//--------------------------------------------------------------------
void p0(const string& s)
{
	//@TODO implement
	throw new std::runtime_error("unimplemented p0(const std::string & s) called");
}

//--------------------------------------------------------------------
void p1(int i/* = 5*/)
{
	//@TODO implement
	throw new std::runtime_error("unimplemented p1(int i) called");
}

//--------------------------------------------------------------------
void p2(int i/* = 5*/, const std::string& s/* = std::string(5, 'x')*/)
{
	//@TODO implement
	throw new std::runtime_error("unimplemented p2(int i,const std::string & s) called");
}

//--------------------------------------------------------------------
void A::m0(const std::string&) const
{
	//@TODO implement
	throw new std::runtime_error("unimplemented A::m0(const std::string & s) const:const called");
}

namespace n0
{

}

//--------------------------------------------------------------------
std::string& n0::State::operator[] (const std::string& key)
{
	//@TODO implement
	throw new std::runtime_error("unimplemented n0::State::operator [](const std::string & key) called");
}

//--------------------------------------------------------------------
n0::State::SS n0::Foo::foo(n0::State::SS s)
{
	//@TODO implement
	throw new std::runtime_error("unimplemented n0::Foo::foo(State::SS s) called");
}
