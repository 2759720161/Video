"""Port the pinned Node core's range views to equivalent ordinary containers.

This changes only Node core files, not V8's host-tool headers. SDK libc++ leaves
incomplete ranges disabled and does not provide all the views Node 24 uses.
"""
from pathlib import Path
import re
import sys

root = Path(sys.argv[1]) / 'node-v24.2.0' / 'src'

def write_changed(path, value):
    if not path.exists() or path.read_text(encoding='utf-8') != value:
        path.write_text(value, encoding='utf-8')

def replace_once(name, original, replacement):
    path = root / name
    value = path.read_text(encoding='utf-8')
    if replacement in value:
        return
    if value.count(original) != 1:
        raise RuntimeError('Unexpected pinned Node source: ' + name)
    write_changed(path, value.replace(original, replacement, 1))

# Node 24.2's Undici eagerly starts its WASM HTTP parser while merely loading
# Headers/FormData. Defer that work until an HTTP/1 connection actually needs it,
# as newer Undici does. Native fetch still requires WASM; no parser is emulated.
replace_once('../deps/undici/undici.js', '''    var llhttpPromise = lazyllhttp();
    llhttpPromise.catch();''', '''    var llhttpPromise = null;''')
replace_once('../deps/undici/undici.js', '''      llhttpInstance = await llhttpPromise;''', '''      llhttpPromise ||= lazyllhttp();
      llhttpInstance = await llhttpPromise;''')

replace_once('node_builtins.h', '''  [[nodiscard]] std::ranges::keys_view<
      std::ranges::ref_view<const BuiltinSourceMap>>
  GetBuiltinIds() const;''', '''  [[nodiscard]] std::vector<std::string> GetBuiltinIds() const;''')
replace_once('node_builtins.cc', '''std::ranges::keys_view<std::ranges::ref_view<const BuiltinSourceMap>>
BuiltinLoader::GetBuiltinIds() const {
  return std::views::keys(*source_.read());
}''', '''std::vector<std::string> BuiltinLoader::GetBuiltinIds() const {
  auto source = source_.read();
  std::vector<std::string> ids;
  ids.reserve(source->size());
  for (const auto& entry : *source) ids.push_back(entry.first);
  return ids;
}''')

# Builtin IDs now use the existing vector overload, so the sole elements_view
# overload is unnecessary. Preserve every other ToV8Value conversion.
for name, expression in [
    ('util.h', r'template <typename T, std::size_t U>\ninline v8::MaybeLocal<v8::Value> ToV8Value\(\s*v8::Local<v8::Context> context,\s*const std::ranges::elements_view<T, U>& vec,\s*v8::Isolate\* isolate = nullptr\);\n'),
    ('util-inl.h', r'template <typename T, std::size_t U>\nv8::MaybeLocal<v8::Value> ToV8Value\(\s*v8::Local<v8::Context> context,\s*const std::ranges::elements_view<T, U>& vec,\s*v8::Isolate\* isolate\) \{[\s\S]*?\n}\n')
]:
    path = root / name
    value = path.read_text(encoding='utf-8')
    if 'std::ranges::elements_view' not in value:
        continue
    value, count = re.subn(expression, '', value)
    if count != 1 or 'std::ranges::elements_view' in value:
        raise RuntimeError('Unexpected view conversion: ' + name)
    write_changed(path, value)

replace_once('node_options-inl.h', '''      std::ranges::for_each(std::ranges::subrange(f, l) | std::views::values,
                            [&](const auto& value) {
                              if (value.type == kV8Option) {
                                v8_args->push_back(value.name);
                              } else {
                                *value.target_field->template Lookup<bool>(
                                    options) = value.target_value;
                              }
                            });''', '''      for (auto implication = f; implication != l; ++implication) {
        const auto& value = implication->second;
        if (value.type == kV8Option) {
          v8_args->push_back(value.name);
        } else {
          *value.target_field->template Lookup<bool>(options) = value.target_value;
        }
      }''')

write_changed(root / 'node_sdk_compat.h', '''#ifndef NODE_SDK_COMPAT_H_
#define NODE_SDK_COMPAT_H_
#include <string_view>
#include <vector>
namespace node {
namespace sdk_compat {
// Match split_view for an empty input and trailing or consecutive delimiters.
inline std::vector<std::string_view> SplitComma(std::string_view input) {
  std::vector<std::string_view> result;
  if (input.empty()) return result;
  std::size_t start = 0;
  for (;;) {
    const auto end = input.find(',', start);
    if (end == std::string_view::npos) {
      result.push_back(input.substr(start));
      return result;
    }
    result.push_back(input.substr(start, end - start));
    start = end + 1;
  }
}
}  // namespace sdk_compat
}  // namespace node
#endif
''')

replace_once('node_options.cc', '#include "node_options.h"', '#include "node_options.h"\n#include "node_sdk_compat.h"')
replace_once('node_options.cc', '  auto entries = std::views::split(inspect_publish_uid_string, ","sv);',
             '  auto entries = sdk_compat::SplitComma(inspect_publish_uid_string);')
replace_once('node_v8_platform-inl.h', '#include "node_platform.h"',
             '#include "node_platform.h"\n#include "node_sdk_compat.h"')
replace_once('node_v8_platform-inl.h', '''      auto categories = std::views::split(
          per_process::cli_options->trace_event_categories, ","sv);''',
             '''      auto categories = sdk_compat::SplitComma(
          per_process::cli_options->trace_event_categories);''')

for name in ['node_builtins.h', 'node_builtins.cc', 'util.h', 'util-inl.h',
             'node_options-inl.h', 'node_options.cc', 'node_v8_platform-inl.h']:
    value = (root / name).read_text(encoding='utf-8')
    if re.search(r'std::(?:ranges|views)::', value):
        raise RuntimeError('Unreviewed Node range operation: ' + name)
print('Node core SDK compatibility prepared.', flush=True)
