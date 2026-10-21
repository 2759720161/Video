"""Run in WSL; compare the actual SDK adaptations with standard C++ algorithms."""
from pathlib import Path
import re
import subprocess
import sys
import tempfile

work = Path(sys.argv[1])
source = work / 'node-v24.2.0' / 'src'
functions = []
for index, name in enumerate(['descriptor-array-inl.h', 'transitions-inl.h']):
    header = (work / 'compat-headers/src/objects' / name).read_text(encoding='utf-8')
    match = re.search(r'  int (number|i) = 0;\n  int search_upper = end;[\s\S]*?\n  }\n', header)
    if match is None:
        raise RuntimeError('Expected adapted binary search not found: ' + name)
    functions.append(f'''int Find{index}(const std::vector<Entry>& values, uint32_t hash) {{
  int end = static_cast<int>(values.size());
  auto GetSortedKey = [&](int i) {{ return &values[i]; }};
  auto GetKey = [&](int i) {{ return &values[i]; }};
{match[0]}
  return {match[1]};
}}''')

program = r'''
#include "node_sdk_compat.h"
#include <algorithm>
#include <cassert>
#include <cstdint>
#include <iostream>
#include <limits>
#include <random>
#include <ranges>
#include <string>
struct Entry { uint32_t value; uint32_t hash() const { return value; } };
''' + '\n'.join(functions) + r'''
int main() {
  std::mt19937 random(24020);
  std::vector<std::string> inputs{"", ",", ",,", "a", "a,", ",a", "a,,b", "stderr,http"};
  for (int i = 0; i < 1000; i++) {
    std::string value;
    for (int j = random() % 128; j > 0; j--) value += "ab,"[random() % 3];
    inputs.push_back(value);
  }
  for (const auto& input : inputs) {
    std::vector<std::string> expected;
    for (const auto& part : std::views::split(input, ',')) expected.emplace_back(part.begin(), part.end());
    auto actual = node::sdk_compat::SplitComma(input);
    assert(actual.size() == expected.size());
    for (std::size_t i = 0; i < actual.size(); i++) assert(actual[i] == expected[i]);
  }
  int searches = 0;
  for (int trial = 0; trial < 200; trial++) {
    std::vector<Entry> values(trial < 8 ? trial : random() % 256);
    for (auto& value : values) value.value = random() % 64;
    std::sort(values.begin(), values.end(), [](Entry a, Entry b) { return a.value < b.value; });
    for (int probe = 0; probe < 64; probe++) {
      uint32_t key = probe == 0 ? 0 : probe == 1 ? std::numeric_limits<uint32_t>::max() : random() % 128;
      int expected = std::lower_bound(values.begin(), values.end(), key,
          [](Entry a, uint32_t b) { return a.value < b; }) - values.begin();
      assert(Find0(values, key) == expected);
      assert(Find1(values, key) == expected);
      searches++;
    }
  }
  std::cout << "{\"splitCases\":" << inputs.size() << ",\"searchCasesPerImplementation\":" << searches << "}\n";
}
'''
with tempfile.TemporaryDirectory(prefix='video-sdk-compat-') as directory:
    cpp = Path(directory) / 'probe.cpp'
    binary = Path(directory) / 'probe'
    cpp.write_text(program, encoding='utf-8')
    subprocess.run(['g++', '-std=c++20', '-O2', '-I' + str(source), str(cpp), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
