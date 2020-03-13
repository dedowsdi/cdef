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

void test_global_single_anonymous_default(const std::string& s, int i)
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

void test_global_space_type(unsigned a)
{
}

void test_global_space_type_anonymous(long long, signed int, unsigned)
{
}

void test_same_sig_different_scope(const std::string& s)
{
}

using namespace std;
void test_namespace_different(const string& s)
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

  void C0::test_N_C0_reload(int a, int b)
  {
  }

  void C0::test_N_C0_reload(int a, int b) const
  {
  }

  void C0::test_N_C0_reload(int a, int b, float c) const
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

  namespace
  {
      void annoy_manual_gen_func_head_test();
  }

}

int main(int argc, char *argv[])
{
  return 0;
}
