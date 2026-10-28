// Independent EchoLingo IPC wrapper. Mozilla/Bergamot inference remains MPL-2.0.
#include <filesystem>
#include <fstream>
#include <iostream>
#include <map>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>

#include "translator/parser.h"
#include "translator/service.h"
#include "json.hpp"
#ifdef _WIN32
#define NOMINMAX
#include <windows.h>
#include <fcntl.h>
#include <io.h>
#endif

namespace fs = std::filesystem;
namespace mt = marian::bergamot;
constexpr std::size_t kMaxLine = 256 * 1024;
constexpr std::size_t kMaxText = 80000;
constexpr std::size_t kMaxOutput = 256 * 1024;

std::string quoted(const std::string &value) {
  static constexpr char hex[] = "0123456789abcdef";
  std::string out = "\"";
  for (unsigned char c : value) {
    if (c == '"' || c == '\\') { out += '\\'; out += static_cast<char>(c); }
    else if (c < 0x20) {
      out += "\\u00"; out += hex[c >> 4]; out += hex[c & 15];
    } else out += static_cast<char>(c);
  }
  return out + '"';
}

std::string required(const nlohmann::json &request, const char *key) {
  if (!request.contains(key) || !request[key].is_string()) throw std::invalid_argument("INVALID_REQUEST");
  return request[key].get<std::string>();
}

std::string file(const fs::path &root, const std::string &name) {
  fs::path path = root / fs::u8path(name);
  if (!fs::is_regular_file(path) || fs::file_size(path) == 0)
    throw std::runtime_error("MODEL_MISSING");
  return path.u8string();
}

mt::AlignedMemory readMemory(const std::string &filename, std::size_t alignment) {
  // std::filesystem's path overload uses wide file APIs on Windows. The
  // upstream narrow-path file loader cannot safely open Chinese user paths.
  const fs::path path = fs::u8path(filename);
  const auto size = fs::file_size(path);
  if (size == 0 || size > 64 * 1024 * 1024) throw std::runtime_error("MODEL_MISSING");
  std::ifstream stream(path, std::ios::binary);
  mt::AlignedMemory memory(static_cast<std::size_t>(size), alignment);
  if (!stream.read(memory.begin(), static_cast<std::streamsize>(size))) throw std::runtime_error("MODEL_MISSING");
  return memory;
}

std::shared_ptr<mt::TranslationModel> loadModel(const fs::path &root, bool toChinese) {
  const std::string pair = toChinese ? "enzh" : "zhen";
  const fs::path directory = root / (toChinese ? "en-zh" : "zh-en");
  const std::string model = file(directory, "model." + pair + ".intgemm.alphas.bin");
  const std::string shortlist = file(directory, "lex.50.50." + pair + ".s2t.bin");
  const std::string sourceVocab = file(directory, toChinese ? "srcvocab.enzh.spm" : "vocab.zhen.spm");
  const std::string targetVocab = file(directory, toChinese ? "trgvocab.enzh.spm" : "vocab.zhen.spm");
  // JSON is a YAML subset. Paths are quoted with JSON escaping, including Windows backslashes.
  std::string config = "{\"models\":[" + quoted(model) + "],\"vocabs\":[" + quoted(sourceVocab) + "," +
      quoted(targetVocab) + "],\"shortlist\":[" + quoted(shortlist) + ",false],"
      "\"beam-size\":1,\"normalize\":1.0,\"word-penalty\":0,\"max-length-break\":128,"
      "\"mini-batch-words\":512,\"workspace\":128,\"max-length-factor\":2.0,"
      "\"skip-cost\":true,\"cpu-threads\":1,\"quiet\":true,\"quiet-translation\":true,"
      "\"gemm-precision\":\"int8shiftAlphaAll\",\"ssplit-mode\":\"paragraph\"}";
  mt::MemoryBundle memory;
  memory.models.push_back(readMemory(model, 256));
  memory.shortlist = readMemory(shortlist, 64);
  auto sourceMemory = std::make_shared<mt::AlignedMemory>(readMemory(sourceVocab, 64));
  memory.vocabs.push_back(sourceMemory);
  memory.vocabs.push_back(sourceVocab == targetVocab ? sourceMemory :
      std::make_shared<mt::AlignedMemory>(readMemory(targetVocab, 64)));
  return std::make_shared<mt::TranslationModel>(mt::parseOptionsFromString(config, false), std::move(memory));
}

std::string translate(mt::BlockingService &service, const std::shared_ptr<mt::TranslationModel> &model,
                      const std::string &input, bool toChinese) {
  struct Part { std::string prefix, suffix, delimiter; std::size_t index; };
  constexpr auto noTranslation = static_cast<std::size_t>(-1);
  std::vector<Part> parts;
  std::vector<std::string> inputs;
  // Keep every explicit newline and indentation outside the model. Within an
  // English output line, joining decoded sentences needs a space even when the
  // corresponding Chinese sentences had no whitespace between their periods.
  for (std::size_t start = 0; start <= input.size();) {
    const auto newline = input.find('\n', start);
    const auto end = newline == std::string::npos ? input.size() : newline;
    const std::string line = input.substr(start, end - start);
    const auto first = line.find_first_not_of(" \t\r");
    Part part;
    part.index = noTranslation;
    part.delimiter = newline == std::string::npos ? "" : "\n";
    if (first == std::string::npos) part.prefix = line;
    else {
      const auto last = line.find_last_not_of(" \t\r");
      auto content = first;
      // A list/heading marker describes layout, not a word to be translated.
      // Keep it outside the model, which can otherwise drop a leading hyphen.
      auto markerEnd = first;
      if (line[first] == '-' || line[first] == '*' || line[first] == '+' || line[first] == '>') markerEnd = first + 1;
      else if (line.compare(first, 3, "\xe2\x80\xa2") == 0) markerEnd = first + 3;
      else if (line[first] == '#') {
        while (markerEnd < line.size() && markerEnd - first < 6 && line[markerEnd] == '#') ++markerEnd;
      } else if (line[first] >= '0' && line[first] <= '9') {
        while (markerEnd < line.size() && markerEnd - first < 9 && line[markerEnd] >= '0' && line[markerEnd] <= '9') ++markerEnd;
        if (markerEnd < line.size() && (line[markerEnd] == '.' || line[markerEnd] == ')')) ++markerEnd;
        else markerEnd = first;
      }
      if (markerEnd > first && markerEnd < line.size() && (line[markerEnd] == ' ' || line[markerEnd] == '\t')) {
        content = markerEnd;
        while (content <= last && (line[content] == ' ' || line[content] == '\t')) ++content;
      }
      part.prefix = line.substr(0, content);
      part.suffix = line.substr(last + 1);
      part.index = inputs.size();
      inputs.push_back(line.substr(content, last - content + 1));
    }
    parts.push_back(std::move(part));
    if (newline == std::string::npos) break;
    start = newline + 1;
  }
  mt::ResponseOptions option;
  option.concatStrategy = toChinese ? mt::ConcatStrategy::FAITHFUL : mt::ConcatStrategy::SPACE;
  const std::vector<mt::ResponseOptions> options(inputs.size(), option);
  const auto responses = inputs.empty() ? std::vector<mt::Response>() :
      service.translateMultiple(model, std::move(inputs), options);
  std::string result;
  for (const auto &part : parts) {
    result += part.prefix;
    if (part.index != noTranslation) {
      if (part.index >= responses.size()) throw std::runtime_error("OUTPUT_INVALID");
      result += responses[part.index].target.text;
    }
    result += part.suffix;
    result += part.delimiter;
    if (result.size() > kMaxOutput) throw std::runtime_error("OUTPUT_INVALID");
  }
  return result;
}

// Avoid std::getline's unbounded allocation even when launched outside the app.
bool readLine(std::string &line) {
  line.clear();
  bool overflow = false;
  char c;
  while (std::cin.get(c)) {
    if (c == '\n') break;
    if (line.size() < kMaxLine) line += c;
    else overflow = true;
  }
  if (overflow) throw std::invalid_argument("INPUT_TOO_LARGE");
  return !line.empty() || !std::cin.eof();
}

int engineMain(const std::vector<std::string> &arguments) {
#ifdef _WIN32
  _setmode(_fileno(stdin), _O_BINARY);
  _setmode(_fileno(stdout), _O_BINARY);
#endif
  fs::path modelRoot;
  bool once = false;
  for (std::size_t i = 1; i < arguments.size(); ++i) {
    const std::string &argument = arguments[i];
    if (argument == "--model-root" && i + 1 < arguments.size()) modelRoot = fs::u8path(arguments[++i]);
    else if (argument == "--once") once = true;
    else if (argument == "--version") {
      std::cout << "echolingo-offline-engine 1 mozilla-69455acaecbe8650cdba988dbcf7c10ca20e7c48\n";
      return 0;
    } else { std::cerr << "Invalid offline engine arguments\n"; return 2; }
  }
  if (modelRoot.empty() || !modelRoot.is_absolute()) {
    std::cerr << "An absolute --model-root is required\n"; return 2;
  }

  mt::BlockingService::Config serviceConfig;
  serviceConfig.logger.level = "off";
  mt::BlockingService service(serviceConfig);
  std::map<bool, std::shared_ptr<mt::TranslationModel>> models;
  do {
    std::string id, line;
    try {
      if (!readLine(line)) break;
      const auto request = nlohmann::json::parse(line);
      if (!request.is_object() || request.size() != 4) throw std::invalid_argument("INVALID_REQUEST");
      id = required(request, "id");
      if (id.empty() || id.size() > 128) throw std::invalid_argument("INVALID_REQUEST");
      const std::string source = required(request, "source"), target = required(request, "target");
      const bool toChinese = source == "en" && target == "zh";
      if (!toChinese && !(source == "zh" && target == "en")) throw std::invalid_argument("LANGUAGE_UNSUPPORTED");
      std::string input = required(request, "text");
      if (input.empty() || input.size() > kMaxText || input.find('\0') != std::string::npos)
        throw std::invalid_argument("INPUT_INVALID");
      auto &model = models[toChinese];
      if (!model) model = loadModel(modelRoot, toChinese);
      const std::string result = translate(service, model, input, toChinese);
      std::cout << "{\"id\":" << quoted(id) << ",\"text\":" << quoted(result) << "}\n" << std::flush;
    } catch (const std::exception &error) {
      std::string code = error.what();
      if (code != "INVALID_REQUEST" && code != "INPUT_TOO_LARGE" && code != "LANGUAGE_UNSUPPORTED" &&
          code != "INPUT_INVALID" && code != "MODEL_MISSING" && code != "OUTPUT_INVALID") code = "INFERENCE_FAILED";
      // Error messages never contain the submitted source or filesystem paths.
      std::cout << "{\"id\":" << quoted(id) << ",\"code\":" << quoted(code)
                << ",\"error\":\"Offline translation could not complete.\"}\n" << std::flush;
    }
  } while (!once && std::cin.good());
  return 0;
}

#ifdef _WIN32
int wmain(int argc, wchar_t **argv) {
  std::vector<std::string> arguments;
  for (int i = 0; i < argc; ++i) {
    const int length = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, argv[i], -1, nullptr, 0, nullptr, nullptr);
    if (length <= 0) return 2;
    std::string argument(static_cast<std::size_t>(length), '\0');
    if (!WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, argv[i], -1, argument.data(), length, nullptr, nullptr)) return 2;
    argument.pop_back();
    arguments.push_back(std::move(argument));
  }
  return engineMain(arguments);
}
#else
int main(int argc, char **argv) {
  return engineMain(std::vector<std::string>(argv, argv + argc));
}
#endif
