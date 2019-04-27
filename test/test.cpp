#include "test.h"

void test_global_blank()
{
}

void test_global_single(int i)
{
}

void test_global_single_default(int i)
{
}

void test_global_single_default_vec(const std::vector<int>& v)
{
}

void test_global_multiple(int a, float b, bool c)
{
}

void test_global_anonymous(int a)
{
}

void test_global_different_name(int b)
{
}

void test_same_sig_different_scope(const std::string& s)
{
}

namespace N
{
  void test_N_blank()
  {
  }

  void test_same_sig_different_scope(const std::string& s)
  {
  }

  void C0::test_N_C0_blank()
  {
  }

  void test_N_C0_reload(int a, int b)
  {
  }

  void test_N_C0_reload(int a, int b) const
  {
  }

  void test_N_C0_reload(int a, int b, float c) const
  {
  }

  void C0::operator()()
  {
  }

  void C0::operator+(int i)
  {
  }

  void C0::test_same_sig_different_scope(const std::string& s)
  {
  }

  namespace N_N
  {
    void test_N_N_blank()
    {
    }
  }

}
