/*
 * Inline, template function and method of template class will be defined at the
 * end of their namespace or current file.
 * Others will be defined in source file.
 *
 * If there exists using namespace nsChild in scope nsParent in source file. All
 * functions of nsChild will be defined in the end or beginning of nsParent
 * scope, depends of your defining sequence. eg:
 *
 * .h:
 * namespace nsParent{
 *   void f0()
 *   void f1()
 *   namespace nsChild(){
 *     void f2()
 *     void f3()
 *   }
 * }
 *
 * .cpp:
 * namespace nsParent{
 *   using namespace nsChild;
 * }
 *
 * if you define f0 or f1 first, f2 and f3 will be placed after f1
 * if you define f2 or f3 first, f0 and f1 will be placed after f3
 *
 * The same rule applies if nsParent is global.
 *
 */
#include <string>

void globalFunction0(){}

inline void globalPrototype0(int i, int j = 5);

template<
typename T0,
typename T1,
typename T2
>
void globalPrototype1(bool b);

class A
{
  public:

    inline void A_Prototype0(const std::string& s);

    inline void A_Prototype1(bool b);

    void A_Function0(const std::string& s) {
    }

    void A_Prototype2(float f);

    void A_Prototype3(const std::string& s);
    
    virtual A_PureVirtual0(bool b) = 0;
};

struct B
{
  public:
    void B_Prototype0(int i);
};

namespace n0
{
  class n0_A
  {
    public:

      inline void n0_A_Prototype0(const std::string& s);

      inline void n0_A_Prototype1(bool b);

      void n0_A_Function0(const std::string& s) {
      }

      void n0_A_Prototype2(float f);

      void n0_A_Prototype3(int i);
      
      virtual n0_A_PureVirtual0(bool b) = 0;

      void operator ()(int i);

      void operator*(float f);

      void operator*=(float f);
  };
}

namespace n1
{
  class n1_A
  {
    public:
      void n1_A_Prototype0(bool b);
  };

  template<typename T>
  class n1_B
  {
    public:
      void n1_B_Prototype0(int i);

      void n1_B_Prototype1(float f);
  };
}

namespace n2
{
  void n2_prototype0();
  namespace n2_0
  {
    void n2_0_prototype1();
  }
}
