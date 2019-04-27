#include <iostream>
#include <string>
#include <vector>

void test_global_blank();

void test_global_single(int i);

void test_global_single_default(int i = 5);

void test_global_single_default_vec(const std::vector<int>& v = std::vector<int>{1,2,3,4,5});

void test_global_multiple(int a, float b, bool c);

void test_global_anonymous(int);

void test_global_different_name(int a);

void test_same_sig_different_scope(const std::string& s);

template <typename T>
void test_global_template_blank();

namespace N
{
  void test_same_sig_different_scope(const std::string& s);

  class C0
  {
  public:
    void test_N_C0_blank();

    void test_N_C0_reload(int a, int b);
    void test_N_C0_reload(int a, int b) const;
    void test_N_C0_reload(int a, int b, float c) const;

    void operator()();

    void operator+(int i);

    void test_same_sig_different_scope(const std::string& s);
  };

  template<typename T>
  class T0
  {
  public:
    void test_N_T0_blank();
  };

  namespace N_N
  {
    void test_N_N_blank();
  }

}

template <class T>
void test_global_template_blank()
{
}

template<typename T>
void N::T0<T>::test_N_T0_blank()
{
}
