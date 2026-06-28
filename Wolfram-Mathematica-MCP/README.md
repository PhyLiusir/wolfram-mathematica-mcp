# 🐺 Wolfram Mathematica MCP Agent

> **Wolfram Language × MCP (Model Context Protocol) — 持久化内核科学计算服务**

[![Wolfram](https://img.shields.io/badge/Wolfram-14.3%2B-dd1100?logo=wolfram-mathematica)](https://www.wolfram.com/engine/)
[![MCP](https://img.shields.io/badge/MCP-Enabled-blue)](https://modelcontextprotocol.io/)
[![License](https://img.shields.io/badge/License-MIT-green)](./LICENSE)
[![Tools](https://img.shields.io/badge/Tools-30-orange)](#-mcp-工具列表)

通过 MCP 协议为 Claude Code / AI Agent 提供持久化的 Wolfram Language 计算内核，集成 6 大物理计算包（FeynCalc, FeynArts, Package-X, FIRE, xAct, FeynHelpers）。

```
Claude Code ──▶ math.exe ──▶ StartMCPServer ──▶ 30 MCP Tools
                  │                                    │
                  └── WolframLanguageSession ◀─────────┘
                       (持久化内核，<100ms 热调用)
```

---

## 📑 目录

- [特性](#-特性)
- [架构](#-架构)
- [项目结构](#-项目结构)
- [前置条件](#-前置条件)
- [安装](#-安装)
- [配置](#-配置)
- [MCP 工具列表](#-mcp-工具列表)
- [安全沙箱](#-安全沙箱)
- [工作流](#-工作流)
- [版本历史](#-版本历史)
- [License](#-license)

---

## ✨ 特性

| 特性 | 说明 |
|------|------|
| **持久化内核** | WolframLanguageSession 跨调用持久，变量/定义/包在会话期间保持 |
| **30 MCP 工具** | 7 内置(Wolfram Language 通用) + 23 自定义(数学8 + 绘图3 + 量子场论10 + 会话2) |
| **6 大物理包** | FeynCalc, FeynArts, Package-X, FIRE, xAct, FeynHelpers 集成 |
| **三级安全沙箱** | Permissive / Moderate / Strict，默认 Strict 模式防御注入 |
| **LRU 结果缓存** | 重复计算 <1ms 返回，支持跨工具共享 |
| **双轨工作流** | 简单问题一步到位；复杂问题先规划→分解→分步验证→组装结果 |
| **LaTeX/PDF 导出** | Python 独立脚本，不依赖 WolframKernel，支持中文 XeLaTeX |
| **全部工具带 Timeout** | 防止死循环，支持自定义超时 |

---

## 🏗 架构

```
┌─────────────────────────────────────────────────────────┐
│                    Claude Code (AI Agent)                │
│                      MCP 协议 (stdio)                    │
└──────────────────────────┬──────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────┐
│              start_mcp.wls (MCP 启动器 v7.6)             │
│  ① Quiet[] 加载 Wolfram`AgentTools` + WolframQFT 包       │
│  ② 定义 23 个 LLMTool 对象                                │
│  ③ 合并 7 个官方内置工具 → 30 工具终极军火库              │
│  ④ StartMCPServer[customServer]                          │
└──────────────────────────┬──────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────┐
│              WolframQFT Package (v1.0.0)                 │
│  ┌──────────┬──────────┬──────────┬──────────┬────────┐ │
│  │ Common   │ MathTools│ PlotTools│ Physics  │Session │ │
│  │ safeEval │ Solve    │ 2D Plot  │ Tools    │Tools   │ │
│  │ loadPkg  │ Integrate│ 3D Plot  │ FeynCalc │Info    │ │
│  │ catchTop │ Diff'iate│ ParaPlot │ Dirac    │Reset   │ │
│  │ Cache    │ Simplify │          │ Color    │        │ │
│  │ Sandbox  │ Matrix   │          │ Loop     │        │ │
│  │          │ Numeric  │          │ Diagram  │        │ │
│  │          │ Assume   │          │ PackX    │        │ │
│  │          │          │          │ FIRE     │        │ │
│  │          │          │          │ xAct     │        │ │
│  │          │          │          │ Bridge   │        │ │
│  └──────────┴──────────┴──────────┴──────────┴────────┘ │
└─────────────────────────────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────┐
│            Wolfram Engine 14.3+ (持久化内核)              │
│  FeynCalc 9.3 | FeynArts 3.11 | Package-X 2.1            │
│  FIRE 6.5 | xAct 1.2 | FeynHelpers 1.2                   │
└─────────────────────────────────────────────────────────┘
```

---

## 📁 项目结构

```
wolfram-mathematica-mcp/
├── README.md                          # 本文件
├── LICENSE                            # MIT License
├── .gitignore
│
├── mcp-server/                        # MCP 服务器启动脚本
│   ├── start_mcp.wls                  # 主启动器 (386 行, v7.6)
│   └── setup_once.wl                  # 一次性安装脚本 (398 行)
│
├── WolframQFT/                        # 自定义 Wolfram 包 (~1424 行 WL)
│   ├── PacletInfo.m                   # 包元数据
│   └── Kernel/
│       ├── init.m                     # 包入口，自动加载全部子模块
│       ├── Common.wl                  # 安全执行 / 包加载 / 缓存 / 沙箱
│       ├── MathTools.wl               # 8 个数学工具
│       ├── PhysicsTools.wl            # 10 个量子场论工具
│       ├── PlotTools.wl               # 3 个绘图工具
│       ├── SessionTools.wl            # 会话信息 / 内核重置
│       ├── ServerConfig.wl            # 服务器配置常量
│       ├── setup_v3.wls               # 交互式安装向导
│       └── _test.wl                   # 测试占位
│
├── scripts/                           # 辅助脚本
│   └── wolfram_pdf_standalone.py      # Python PDF 生成器 (722 行)
│
└── config/                            # 配置示例
    └── mcp-config-example.json        # Claude Code MCP 配置模板
```

---

## 📋 前置条件

| 组件 | 版本要求 | 说明 |
|------|----------|------|
| **Wolfram Engine** | 14.3.0+ | 免费版 [Wolfram Engine](https://www.wolfram.com/engine/) 即可，无需 Mathematica 许可证 |
| **Wolfram AgentTools** | 2.1.0+ | Wolfram 官方 paclet，通过 `PacletInstall` 安装 |
| **FeynCalc** | 9.3+ | 高能物理费曼图计算 |
| **FeynArts** | 3.11+ | 费曼图生成器 |
| **Package-X** | 2.1+ | 单圈 Passarino-Veltman 函数解析计算 |
| **FIRE** | 6.5+ | 多圈 IBP 约化 |
| **xAct** | 1.2+ | 广义相对论张量代数 |
| **FeynHelpers** | 1.2+ | FeynCalc ↔ Package-X 桥梁 |
| **Python** | 3.11+ | 仅 PDF 导出功能需要 |
| **XeLaTeX** | (任意版本) | 仅 PDF 导出功能需要 |
| **Claude Code** | 最新版 | 或任何支持 MCP 的 AI 客户端 |

### 安装前置依赖

```wolfram
(* 在 Wolfram 中运行 *)
PacletInstall["Wolfram/AgentTools"];
PacletInstall["FeynCalc"];
PacletInstall["FeynArts"];
PacletInstall["PackageX"];
PacletInstall["FIRE"];
PacletInstall["xAct"];
PacletInstall["FeynHelpers"];
```

---

## 🔧 安装

### 1. 克隆仓库

```bash
git clone https://github.com/<your-username>/wolfram-mathematica-mcp.git
cd wolfram-mathematica-mcp
```

### 2. 安装 WolframQFT 包

将 `WolframQFT/` 目录复制到 Wolfram 用户应用目录：

```powershell
# Windows
Copy-Item -Recurse WolframQFT "$env:APPDATA\Mathematica\Applications\WolframQFT"

# macOS / Linux
cp -r WolframQFT ~/.Mathematica/Applications/WolframQFT
# 或
cp -r WolframQFT ~/.WolframEngine/Applications/WolframQFT
```

### 3. 配置 MCP 服务器路径

编辑 `mcp-server/start_mcp.wls`，确认以下路径正确：

- `$UserBaseDirectory` 指向正确的 Wolfram 用户目录
- WolframQFT 包路径自动从 `$UserBaseDirectory/Applications/WolframQFT/` 加载

### 4. 一次性设置（仅需运行一次）

在 Mathematica 笔记本或 wolframscript 中运行 `setup_once.wl`：

```bash
wolframscript -file mcp-server/setup_once.wl
```

这会创建持久化的 `WolframQFT` MCP 服务器配置。

### 5. 配置 Claude Code MCP

将以下配置添加到 `~/.claude/.mcp.json`：

```json
{
  "mcpServers": {
    "mathematica": {
      "command": "<your-wolfram-engine-path>\\math.exe",
      "args": ["-noprompt", "-script", "<repo-path>\\mcp-server\\start_mcp.wls"],
      "env": {
        "WOLFRAM_KERNEL": "<your-wolfram-engine-path>\\WolframKernel.exe",
        "WOLFRAM_TIMEOUT": "300"
      }
    }
  }
}
```

> 参见 `config/mcp-config-example.json` 获取完整示例。

### 6. 验证安装

重启 Claude Code，然后尝试：

```
wolfram_evaluate --code "2+2"
```

应返回 `4`。

---

## 🛠 MCP 工具列表

### 🔢 数学工具 (8)

| 工具名 | 功能 | 超时 |
|--------|------|------|
| `wolfram_evaluate` | 执行任意 Wolfram Language 代码 | 60s |
| `wolfram_solve` | 解方程 (symbolic/numeric/differential/numeric_diff) | 120s |
| `wolfram_integrate` | 符号积分 (定积分/不定积分/多重积分) | 180s |
| `wolfram_differentiate` | 求导 (高阶/偏导) | 60s |
| `wolfram_simplify` | 化简 (12种方法 + auto 自动迭代) | 120s |
| `wolfram_matrix` | 矩阵运算 (10种: det/inv/eigen/SVD/...) | 120s |
| `wolfram_numeric` | 数值计算 (NIntegrate/NSum/FindRoot/NMinimize/...) | 180s |
| `wolfram_assume` | 管理 $Assumptions (set/add/clear/view) | 即时 |

### 📊 绘图工具 (3)

| 工具名 | 功能 |
|--------|------|
| `wolfram_plot` | 2D 函数曲线 → base64 PNG |
| `wolfram_plot3d` | 3D 曲面图 → base64 PNG |
| `wolfram_parametric_plot` | 参数曲线图 → base64 PNG |

### ⚛️ 量子场论工具 (10)

| 工具名 | 功能 |
|--------|------|
| `physics_load_package` | 加载物理包 (FeynCalc/FeynArts/PackageX/FIRE/xAct/FeynHelpers) |
| `physics_feyncalc_amplitude` | FeynCalc 散射振幅计算 (自旋子/γ矩阵) |
| `physics_dirac_trace` | Dirac γ矩阵求迹 |
| `physics_color_factor` | SU(N) 色因子计算 (SUNSimplify) |
| `physics_loop_integral` | 圈积分约化 (tid 张量分解 / PaVeReduce) |
| `physics_feynman_diagram` | 费曼图生成 (内置: compton/bhabha/moller/pair_annihilation/gg_scatter) → base64 PNG |
| `physics_package_x` | Package-X 单圈 PaVe 函数解析计算 (含 UV 1/ε 极点) |
| `physics_fire_reduce` | FIRE 多圈 IBP 约化 → master integrals |
| `physics_xact_tensor` | xAct 弯曲时空张量代数 (Ricci/Riemann/Einstein/Weyl/VarD) |
| `physics_feynhelpers_convert` | FeynCalc ↔ Package-X 循环积分互转 |

### 🔧 会话工具 (2)

| 工具名 | 功能 |
|--------|------|
| `wolfram_session_info` | 查看内核状态：版本/已加载包/安全级别/缓存统计 |
| `wolfram_reset_kernel` | 重置内核 (需 confirm=True) |

### 📦 内置 Wolfram Language 工具 (7)

| 工具名 | 功能 |
|--------|------|
| `WolframLanguageContext` | 获取当前 Wolfram 语言上下文 |
| `WolframLanguageEvaluator` | 高级 Wolfram 语言求值器 |
| `ReadNotebook` | 读取 Wolfram Notebook |
| `WriteNotebook` | 写入 Wolfram Notebook |
| `SymbolDefinition` | 查询符号定义 |
| `CodeInspector` | 代码检查 |
| `TestReport` | 测试报告 |

---

## 🛡 安全沙箱

三级安全机制，默认 Strict 模式：

| 级别 | 允许 | 禁止 |
|------|------|------|
| **Permissive** | 所有操作 | — |
| **Moderate** | 计算、符号操作、绘图 | 文件读写、网络、外部进程 |
| **Strict** (默认) | 纯计算、符号操作 | 文件/网络/进程 + 危险符号 (DeleteFile, Run, ...) |

缓存机制：LRU 最多 256 项，重复调用 <1ms 返回，跨工具共享。修改 $Assumptions 自动清空缓存。

---

## 🔄 工作流

### 双轨工作流 (v7.3+)

```
┌─────────────────────┐
│   用户提问           │
└─────────┬───────────┘
          │
    ┌─────▼─────┐
    │ 复杂度判断  │
    └──┬──────┬──┘
       │      │
   简单│      │复杂
       │      │
┌──────▼──┐ ┌─▼──────────────┐
│ 直接编写 │ │ ① 内部思考规划  │
│ WL 代码  │ │ ② 分解为明确步骤│
│ ↓       │ │ ③ 分步调用验证  │
│ 计算结果 │ │ ④ 组装最终结果  │
│ ↓       │ └────────────────┘
│ 输出结果 │
└──────────┘
```

- **简单问题**：跳过化简询问循环，直接编写 Wolfram 代码 → 计算 → 输出
- **复杂问题**：先规划 → 分解步骤 → 逐步调用 Wolfram 验证 → 组装结果
- AskUserQuestion 化简循环仅保留给结果形式不明确的中间步骤

---

## 📝 版本历史

| 版本 | 日期 | 变更 |
|------|------|------|
| **v7.6** | 2025-06 | Quiet[] 包加载防 stdout 污染；KeyTake+Append 防 Tag Protected 错误 |
| **v7.5** | 2025-06 | 修复 start_mcp.wls 上下文错误 |
| **v7.3** | 2025-05 | 双轨工作流：简单问题一步到位，复杂问题分步验证 |
| **v7.2** | 2025-05 | PhysicsTools.wl v3.1 — feynmanDiagram 重写；Common.wl v1.2 — safeEval 增强 |
| **v7.1** | 2025-05 | 修复 start_mcp.wls 包加载，补齐全部 23 LLMTool 定义 |
| **v7.0** | 2025-04 | 三级安全沙箱、LRU 缓存、符号构造消除注入、auto 自动化简、全部工具 Timeout |
| **v1.0** | 2025-03 | 初始版本：WolframQFT 包 + MCP 服务器 |

---

## 📄 License

MIT License — 详见 [LICENSE](./LICENSE)

---

## 🙏 致谢

- [Wolfram Research](https://www.wolfram.com/) — Wolfram Engine & AgentTools
- [FeynCalc](https://feyncalc.github.io/) — 高能物理费曼图计算
- [FeynArts](https://feynarts.de/) — 费曼图自动生成
- [Package-X](https://packagex.hepforge.org/) — 单圈解析计算
- [FIRE](https://gitlab.com/feyncalc/FIRE) — IBP 约化
- [xAct](http://www.xact.es/) — 广义相对论张量代数
- [FeynHelpers](https://github.com/FeynCalc/feynhelpers) — FeynCalc ↔ Package-X 桥梁
- [MCP (Model Context Protocol)](https://modelcontextprotocol.io/) — Anthropic

---

<p align="center">
  <sub>Made with ❤️ for theoretical physics computation</sub>
</p>
