# NPU Core RTL 学习导读

这份导读按“控制通路、流式数据通路、定点运算、可观测性”的顺序阅读 Core。当前 Core 保持 IEEE Verilog-2005，方便比较传统 Verilog 与 Tile 层 SystemVerilog 的写法。

## 1. 顶层：先找 valid、ready 和 fire

从 `rtl/core/XingHuo_NPU.v` 开始。启动与权重装载都写成同一种事务模型：

```verilog
start_fire  = start_valid  && start_ready;
weight_fire = weight_valid && weight_ready;
```

`valid` 表示调用者提出请求，`ready` 表示 Core 当前能够接收，`fire` 表示这个时钟沿真正接受事务。它与常见 ready-valid 总线、流水级接口使用同一个规则。

Core 将 `start_ready` 和 `weight_ready` 明确输出。发送方必须保持 valid 和对应 payload，直到某个上升沿 valid 与 ready 同时为1。valid可以先于ready到达；等待期间Core不会修改正在运行的任务。

结果也是ready-valid通道。`result_valid`置位后，若`result_ready=0`，Core会保持`result_matrix`、`result_valid`和`busy`；握手后才释放事务槽位。这展示了常见的下游背压。

波形练习：同时观察 `start_valid`、`start_ready`、`start_fire`、`busy`、`result_valid` 和 `result_ready`。先令`result_ready=0`停顿三拍，再置1，确认结果在停顿期间不变。

## 2. ControlUnit：两段式 Moore 状态机

`rtl/core/ControlUnit.v` 把状态机分成两部分：

- 组合块根据 `state` 和输入计算 `next_state`；
- 时序块在上升沿执行 `state <= next_state`，并更新 `phase` 和 `done`。

`busy`、`array_clear`、`array_step` 和 `result_write_enable` 都由当前状态译码，是 Moore 型输出。数据通路不需要知道状态编码，只接收有业务含义的控制信号。

状态流程为：

```text
IDLE -> CLEAR -> RUN phase 0..3 -> COLLECT -> WRITE_RESULT -> IDLE
```

`next_state = state` 是组合块的默认保持值。非法状态由 `default` 回到 IDLE。这种结构便于检查状态转移，也能防止漏赋值产生锁存器。

状态寄存器、`phase` 计数器和 `done` 脉冲又分别放在三个时序块中。每个寄存器只有一个过程驱动，每个过程只回答一个问题：状态往哪里走、微步骤是否推进、任务是否刚刚完成。

## 3. MatrixFeeder：用错拍对齐空间阵列

`rtl/core/MatrixFeeder.v` 是组合数据选择器。矩阵乘法的不同元素要在正确周期到达正确 PE，因此输入不能同拍直接灌入阵列：

- phase 0 注入 A00；
- phase 1 注入 A10 和 A01；
- phase 2 注入 A11；
- phase 3 不注入新数据，只排空流水。

数据与对应 valid 必须一起变化。下游只能在 valid 为 1 时解释数据，这与总线的有效信息规则相同。

## 4. MacPE：一级带 valid 的寄存流水

`rtl/core/MacPE.v` 包含三类状态：驻留权重、传播激活、传播部分和。每个有效周期计算：

```text
partial_sum_out = partial_sum_in + activation_in * weight
```

`pipeline_fire = enable && compute_valid` 表示当前 PE 接收了一笔有效 MAC 事务。`partial_sum_valid_out` 与计算结果在同一个寄存器边界产生，后级因此不需要猜测数据在哪一拍有效。

驻留权重和 MAC 流水使用两个独立时序块。这样可以直接看出 `clear` 只清流水，而 `weight_load` 只修改权重。

注意优先级：

1. `rst` 清全部状态和权重；
2. `weight_load` 可以更新驻留权重；
3. `clear` 清流水数据，不清权重；
4. `enable` 推进流水。

这一优先级使同一权重可以跨任务复用，同时每次任务都能清空旧 valid。

## 5. SystolicArray：连接规则本身就是数据流

`rtl/core/SystolicArray.v` 实例化四个相同的 `MacPE`：激活向下传播，部分和向右传播。顶层主要描述连接关系，而不是重复编写四份乘加算法。

阅读时沿一笔数据走线：从 `activation_top_col0` 进入 PE00，经过寄存器到 PE10；部分和从 0 进入 PE00，再进入 PE01并流出。结合 `MatrixFeeder` 的错拍即可理解为什么不同矩阵元素会在同一个 PE 对齐。

## 6. ResultCollector：把流重新组成矩阵

阵列右边界每次只流出一个结果，`rtl/core/ResultCollector.v` 使用每列一个索引位，把先后到达的两行结果写入 `sum00/sum10` 或 `sum01/sum11`。

这里展示了流接口常见的接收规则：只有 `result_col*_valid` 为 1 时才更新数据寄存器和索引；无效周期保持已有结果。

两列收集逻辑分别书写，因为它们在硬件上并行、状态也互不依赖。拆开之后无需在一个过程里交错阅读两条数据流。

## 7. 定点数通路：先扩位，再累加，再饱和

数据位宽依次为：

```text
INT8 activation × INT8 weight -> INT16 product
INT16符号扩展 -> INT32 partial sum
INT32 partial sum + INT32 bias -> INT32
算术右移 -> INT8饱和 -> ReLU
```

`MacPE.v` 中显式符号扩展能清楚说明乘积怎样进入32位累加器。`Bias.v` 使用二补码符号规则检测溢出。`Requantize.v` 使用 `>>>` 完成算术右移，并在截断前饱和到 `[-128, 127]`，避免直接取低8位产生回绕。

## 8. VPU：模块级组合链与时钟流水线不同

`rtl/core/VPU.v` 将 Bias、Requantize 和 ReLU 分成三个模块，目的是分离功能和便于替换。它们目前都是组合逻辑，三者之间没有寄存器，所以这是三个组合处理步骤，不是三级时钟流水线。

只有 `result_write_enable` 有效的上升沿才把四个结果一起写入 `result_matrix`。这叫 commit point：外部看到的结果只在完整事务结束时原子更新。

## 9. 粘滞错误与性能计数器

顶层错误寄存器使用 sticky 语义：错误事件只负责置位，直到 `clear_error` 或复位才清除。这是状态寄存器常见写法，软件不必恰好在错误发生的单个周期采样。

四种错误各有一个时序块；当前周期计数、最近任务延迟和任务总数也各有一个时序块。这样的拆分保证单一驱动，同时让每块逻辑保持单一职责。

性能计数器根据 `start_fire` 和内部计算完成事件工作，与矩阵内容及结果通道的背压时长无关。这种可观测性逻辑和算法数据通路解耦，既适合验证，也方便后续映射成软件可读寄存器。

## 推荐波形阅读顺序

一次正常任务建议依次加入：

1. `start_valid/start_ready/start_fire/busy/result_valid/result_ready`；
2. `control_unit.state/phase`；
3. `activation_top_col*` 及其 valid；
4. 每个 PE 的 activation、partial sum 和 valid；
5. `result_col*_stream`、Collector 的四个 sum；
6. `result_write_enable` 和 `result_matrix`。

这样能从事务接受开始，沿着数据路径一直追到最终提交。
