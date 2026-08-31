#include <cstdint>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

#include "VXingHuo_NPU.h"
#include "verilated.h"

namespace {

constexpr int kMaximumWaitCycles = 32;
constexpr int kMaximumReportedFailures = 10;

struct TestVector {
    std::string name;
    std::uint32_t activation;
    std::uint32_t weight;
    std::uint64_t bias;
    std::uint8_t quant_shift;
    std::uint32_t expected;
};

struct VectorSet {
    std::size_t directed_count = 0;
    std::size_t random_count = 0;
    std::uint32_t seed = 0;
    std::vector<TestVector> vectors;
};

std::uint64_t parse_hex(const std::string& text)
{
    std::size_t consumed = 0;
    const std::uint64_t value = std::stoull(text, &consumed, 16);
    if (consumed != text.size()) {
        throw std::runtime_error("非法十六进制字段: " + text);
    }
    return value;
}

std::uint64_t parse_integer(const std::string& text)
{
    std::size_t consumed = 0;
    const std::uint64_t value = std::stoull(text, &consumed, 0);
    if (consumed != text.size()) {
        throw std::runtime_error("非法整数字段: " + text);
    }
    return value;
}

void parse_metadata(const std::string& line, VectorSet& vector_set)
{
    if (line.find("directed=") == std::string::npos) {
        return;
    }

    std::istringstream stream(line.substr(1));
    std::string field;
    while (stream >> field) {
        const std::size_t separator = field.find('=');
        if (separator == std::string::npos) {
            continue;
        }
        const std::string key = field.substr(0, separator);
        const std::string value = field.substr(separator + 1);
        if (key == "directed") {
            vector_set.directed_count = parse_integer(value);
        } else if (key == "random") {
            vector_set.random_count = parse_integer(value);
        } else if (key == "seed") {
            vector_set.seed = parse_integer(value);
        }
    }
}

VectorSet read_vectors(const std::string& path)
{
    std::ifstream input(path);
    if (!input) {
        throw std::runtime_error("无法打开测试向量文件: " + path);
    }

    VectorSet vector_set;
    std::string line;
    std::size_t line_number = 0;
    while (std::getline(input, line)) {
        ++line_number;
        if (line.empty()) {
            continue;
        }
        if (line[0] == '#') {
            parse_metadata(line, vector_set);
            continue;
        }

        std::istringstream stream(line);
        std::string activation;
        std::string weight;
        std::string bias;
        std::string shift;
        std::string expected;
        TestVector vector;
        if (!(stream >> vector.name >> activation >> weight >> bias >> shift >> expected)) {
            throw std::runtime_error("测试向量第" + std::to_string(line_number) + "行字段不足");
        }
        std::string extra;
        if (stream >> extra) {
            throw std::runtime_error("测试向量第" + std::to_string(line_number) + "行字段过多");
        }

        const std::uint64_t shift_value = parse_integer(shift);
        if (shift_value > 31) {
            throw std::runtime_error("测试向量第" + std::to_string(line_number) + "行shift超出范围");
        }
        vector.activation = static_cast<std::uint32_t>(parse_hex(activation));
        vector.weight = static_cast<std::uint32_t>(parse_hex(weight));
        vector.bias = parse_hex(bias);
        vector.quant_shift = static_cast<std::uint8_t>(shift_value);
        vector.expected = static_cast<std::uint32_t>(parse_hex(expected));
        vector_set.vectors.push_back(vector);
    }

    if (vector_set.vectors.empty()) {
        throw std::runtime_error("测试向量文件中没有用例: " + path);
    }
    if (vector_set.vectors.size() != vector_set.directed_count + vector_set.random_count) {
        throw std::runtime_error("测试向量数量与文件头元数据不一致");
    }
    return vector_set;
}

std::string format_hex(std::uint64_t value, int width)
{
    std::ostringstream stream;
    stream << std::hex << std::setw(width) << std::setfill('0') << value;
    return stream.str();
}

int unpack_int8(std::uint32_t packed, int index)
{
    int value = static_cast<int>((packed >> (8 * index)) & 0xFFU);
    return value >= 128 ? value - 256 : value;
}

std::int64_t unpack_int32(std::uint64_t packed, int index)
{
    const std::uint64_t value = (packed >> (32 * index)) & 0xFFFFFFFFULL;
    return value >= 0x80000000ULL
        ? static_cast<std::int64_t>(value) - (std::int64_t{1} << 32)
        : static_cast<std::int64_t>(value);
}

std::string format_matrix(std::uint32_t packed)
{
    std::ostringstream stream;
    stream << "[[" << unpack_int8(packed, 0) << ',' << unpack_int8(packed, 1)
           << "],[" << unpack_int8(packed, 2) << ',' << unpack_int8(packed, 3) << "]]";
    return stream.str();
}

class NpuTestbench {
public:
    NpuTestbench()
    {
        initialize_inputs();
        reset();
    }

    ~NpuTestbench()
    {
        dut_.final();
    }

    bool run(const TestVector& vector, std::size_t index, bool report_failure)
    {
        load_inputs(vector);
        if (!start_and_wait()) {
            if (report_failure) {
                std::cerr << "FAIL #" << index << ' ' << vector.name
                          << ": waiting for done timed out\n";
            }
            return false;
        }

        const std::uint32_t actual = dut_.result_matrix;
        if (actual == vector.expected) {
            return true;
        }
        if (report_failure) {
            report_mismatch(vector, index, actual);
        }
        return false;
    }

private:
    VXingHuo_NPU dut_;

    void initialize_inputs()
    {
        dut_.clk = 0;
        dut_.rst = 0;
        dut_.start = 0;
        dut_.activation_matrix = 0;
        dut_.weight_matrix = 0;
        dut_.bias_vector = 0;
        dut_.quant_shift = 0;
        dut_.eval();
    }

    // 每次调用产生一个上升沿和一个下降沿，调用前后时钟都保持低电平。
    void tick()
    {
        dut_.clk = 1;
        dut_.eval();
        dut_.clk = 0;
        dut_.eval();
    }

    void reset()
    {
        dut_.rst = 1;
        tick();
        tick();
        tick();
        dut_.rst = 0;
        tick();
    }

    void load_inputs(const TestVector& vector)
    {
        dut_.activation_matrix = vector.activation;
        dut_.weight_matrix = vector.weight;
        dut_.bias_vector = vector.bias;
        dut_.quant_shift = vector.quant_shift;
    }

    bool start_and_wait()
    {
        dut_.start = 1;
        tick();
        dut_.start = 0;

        for (int cycle = 0; cycle < kMaximumWaitCycles; ++cycle) {
            tick();
            if (dut_.done) {
                return true;
            }
        }
        return false;
    }

    static void report_mismatch(const TestVector& vector, std::size_t index, std::uint32_t actual)
    {
        std::cerr << "FAIL #" << index << ' ' << vector.name << '\n'
                  << "  activation=" << format_matrix(vector.activation)
                  << " packed=0x" << format_hex(vector.activation, 8) << '\n'
                  << "  weight=" << format_matrix(vector.weight)
                  << " packed=0x" << format_hex(vector.weight, 8) << '\n'
                  << "  bias=[" << unpack_int32(vector.bias, 0) << ','
                  << unpack_int32(vector.bias, 1) << "] packed=0x"
                  << format_hex(vector.bias, 16) << '\n'
                  << "  quant_shift=" << static_cast<int>(vector.quant_shift) << '\n'
                  << "  expected=" << format_matrix(vector.expected)
                  << " packed=0x" << format_hex(vector.expected, 8) << '\n'
                  << "  actual=" << format_matrix(actual)
                  << " packed=0x" << format_hex(actual, 8) << '\n';
    }
};

} // namespace

int main(int argc, char** argv)
{
    Verilated::commandArgs(argc, argv);
    if (argc != 2) {
        std::cerr << "Usage: " << argv[0] << " TEST_VECTOR_FILE\n";
        return 2;
    }

    try {
        const VectorSet vector_set = read_vectors(argv[1]);
        NpuTestbench testbench;
        int failures = 0;

        for (std::size_t index = 0; index < vector_set.vectors.size(); ++index) {
            const bool report_failure = failures < kMaximumReportedFailures;
            if (!testbench.run(vector_set.vectors[index], index, report_failure)) {
                ++failures;
            }
        }

        if (failures == 0) {
            std::cout << "ALL " << vector_set.vectors.size() << " TESTS PASSED\n"
                      << "directed=" << vector_set.directed_count
                      << " random=" << vector_set.random_count
                      << " seed=0x" << std::hex << vector_set.seed << '\n';
            return 0;
        }

        if (failures > kMaximumReportedFailures) {
            std::cerr << "Only the first " << kMaximumReportedFailures
                      << " failures were shown.\n";
        }
        std::cerr << std::dec << failures << " of " << vector_set.vectors.size()
                  << " tests failed\n";
        return 1;
    } catch (const std::exception& error) {
        std::cerr << "ERROR: " << error.what() << '\n';
        return 2;
    }
}
