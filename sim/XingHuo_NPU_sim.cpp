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
constexpr std::uint16_t kExpectedCoreCycles = 6;
constexpr std::uint8_t kErrorStartWhileBusy = 1U << 0;
constexpr std::uint8_t kErrorSwitchWhileBusy = 1U << 2;
constexpr std::uint8_t kErrorStartWithoutWeight = 1U << 3;
constexpr std::uint8_t kErrorSwitchWithoutShadow = 1U << 4;

struct TestVector {
    std::string name;
    std::uint32_t activation;
    std::uint32_t weight;
    std::uint64_t bias;
    std::uint8_t quant_shift;
    std::uint32_t expected;
    std::uint8_t expected_error;
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
        std::string expected_error;
        TestVector vector;
        if (!(stream >> vector.name >> activation >> weight >> bias >> shift >> expected
              >> expected_error)) {
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
        vector.expected_error = static_cast<std::uint8_t>(parse_hex(expected_error));
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
        const bool status_matches = dut_.error_code == vector.expected_error
            && dut_.error == (vector.expected_error != 0)
            && dut_.cycle_count == kExpectedCoreCycles
            && dut_.task_count == index + 1;
        if (actual == vector.expected && status_matches) {
            return true;
        }
        if (report_failure) {
            report_mismatch(vector, index, actual);
            report_status_mismatch(vector, index);
        }
        return false;
    }

    bool load_weight_and_run(const TestVector& vector, std::size_t index, bool report_failure)
    {
        load_shadow(vector.weight);
        switch_weights();
        return run(vector, index, report_failure);
    }

    bool verify_rejected_start()
    {
        clear_errors();
        dut_.activation_matrix = 0;
        dut_.weight_matrix = 0;
        dut_.bias_vector = 0;
        dut_.quant_shift = 0;

        dut_.start = 1;
        tick(); // IDLE接受任务。
        tick(); // busy期间再次观察到start，应置位协议错误。
        dut_.start = 0;

        for (int cycle = 0; cycle < kMaximumWaitCycles; ++cycle) {
            tick();
            if (dut_.done) {
                tick(); // 让可观测性计数器锁存done事件。
                break;
            }
        }

        if (!dut_.error || !(dut_.error_code & kErrorStartWhileBusy)) {
            std::cerr << "FAIL observability: start-while-busy was not reported\n";
            return false;
        }

        clear_errors();
        if (dut_.error || dut_.error_code != 0) {
            std::cerr << "FAIL observability: clear_error did not clear sticky errors\n";
            return false;
        }
        return true;
    }

    bool verify_resident_weights(const VectorSet& vector_set)
    {
        const TestVector& reuse_a = find_vector(vector_set, "resident_reuse_a");
        const TestVector& reuse_b = find_vector(vector_set, "resident_reuse_b");
        const TestVector& shadow_old = find_vector(vector_set, "resident_shadow_old");
        const TestVector& shadow_new = find_vector(vector_set, "resident_shadow_new");

        reset();
        // active bank尚未装载时，start必须被拒绝并留下可诊断错误。
        dut_.start = 1;
        tick();
        dut_.start = 0;
        if (dut_.busy || !(dut_.error_code & kErrorStartWithoutWeight)) {
            std::cerr << "FAIL resident: start without active weight was not rejected\n";
            return false;
        }
        clear_errors();

        load_shadow(reuse_a.weight);
        if (!dut_.shadow_weight_valid || dut_.active_weight_valid) {
            std::cerr << "FAIL resident: shadow load validity is incorrect\n";
            return false;
        }
        switch_weights();
        if (!dut_.active_weight_valid || dut_.shadow_weight_valid) {
            std::cerr << "FAIL resident: active/shadow validity after switch is incorrect\n";
            return false;
        }

        // weight_matrix端口随后变化也不能影响active bank；两次任务复用同一权重。
        if (!run(reuse_a, 0, true) || !run(reuse_b, 1, true)) {
            std::cerr << "FAIL resident: active weight reuse produced a wrong result\n";
            return false;
        }

        // 当前任务使用旧active权重，同时把下一组权重装入shadow。
        load_inputs(shadow_old);
        clear_errors();
        dut_.start = 1;
        tick();
        dut_.start = 0;
        load_shadow(shadow_new.weight);
        if (!wait_for_done() || dut_.result_matrix != shadow_old.expected) {
            std::cerr << "FAIL resident: loading shadow disturbed active computation\n";
            return false;
        }

        // busy期间切换必须被拒绝；上面的任务已结束，因此另起任务触发此检查。
        load_inputs(shadow_old);
        clear_errors();
        dut_.start = 1;
        tick();
        dut_.start = 0;
        dut_.weight_switch = 1;
        tick();
        dut_.weight_switch = 0;
        if (!(dut_.error_code & kErrorSwitchWhileBusy)) {
            std::cerr << "FAIL resident: switch while busy was not reported\n";
            return false;
        }
        if (!wait_for_done() || dut_.result_matrix != shadow_old.expected) {
            std::cerr << "FAIL resident: rejected switch disturbed active computation\n";
            return false;
        }

        clear_errors();
        switch_weights();
        if (!run(shadow_new, 4, true)) {
            std::cerr << "FAIL resident: switched active weight produced a wrong result\n";
            return false;
        }

        // shadow已被消费，再次switch必须被拒绝。
        clear_errors();
        switch_weights();
        if (!(dut_.error_code & kErrorSwitchWithoutShadow)) {
            std::cerr << "FAIL resident: empty shadow switch was not reported\n";
            return false;
        }

        clear_errors();
        return true;
    }

private:
    VXingHuo_NPU dut_;

    void initialize_inputs()
    {
        dut_.clk = 0;
        dut_.rst = 0;
        dut_.start = 0;
        dut_.clear_error = 0;
        dut_.weight_load = 0;
        dut_.weight_switch = 0;
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
        clear_errors();
        dut_.start = 1;
        tick();
        dut_.start = 0;

        for (int cycle = 0; cycle < kMaximumWaitCycles; ++cycle) {
            tick();
            if (dut_.done) {
                // done由ControlUnit产生；顶层计数器在下一上升沿观察并锁存它。
                tick();
                return true;
            }
        }
        return false;
    }

    bool wait_for_done()
    {
        for (int cycle = 0; cycle < kMaximumWaitCycles; ++cycle) {
            tick();
            if (dut_.done) {
                tick();
                return true;
            }
        }
        return false;
    }

    void load_shadow(std::uint32_t weight)
    {
        dut_.weight_matrix = weight;
        dut_.weight_load = 1;
        tick();
        dut_.weight_load = 0;
    }

    void switch_weights()
    {
        dut_.weight_switch = 1;
        tick();
        dut_.weight_switch = 0;
    }

    static const TestVector& find_vector(const VectorSet& vector_set, const std::string& name)
    {
        for (const TestVector& vector : vector_set.vectors) {
            if (vector.name == name) return vector;
        }
        throw std::runtime_error("缺少NPU1.2定向向量: " + name);
    }

    void clear_errors()
    {
        dut_.clear_error = 1;
        tick();
        dut_.clear_error = 0;
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

    void report_status_mismatch(const TestVector& vector, std::size_t index) const
    {
        std::cerr << "  status #" << index
                  << ": expected_error=0x" << format_hex(vector.expected_error, 2)
                  << " actual_error=0x" << format_hex(dut_.error_code, 2)
                  << " cycle_count=" << dut_.cycle_count
                  << " task_count=" << dut_.task_count << '\n';
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
            if (!testbench.load_weight_and_run(
                    vector_set.vectors[index], index, report_failure)) {
                ++failures;
            }
        }

        if (!testbench.verify_rejected_start()) {
            ++failures;
        }
        if (!testbench.verify_resident_weights(vector_set)) {
            ++failures;
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
