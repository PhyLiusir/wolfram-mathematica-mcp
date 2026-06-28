(* ============================================================================
   start_mcp.wls — WolframQFT MCP Server Launcher (v7.6 FIXED)

   v7.6 fix: Quiet[] package loading to prevent stdout pollution of MCP JSON.
   Use KeyTake + Values (restored to original approach) with explicit
   Wolfram`AgentTools` context. Use Append instead of direct assignment
   to avoid "Tag is Protected" errors.

   Architecture: Claude Code -> math.exe -> StartMCPServer -> 30 MCP tools
   Hot <100ms, variables/packages persist across calls.
   ============================================================================ *)

(* ① 加载框架并强制静音，防止任何输出破坏 MCP JSON 协议 *)
Quiet[
    Needs["Wolfram`AgentTools`"];
    Get[FileNameJoin[{$UserBaseDirectory, "Applications", "WolframQFT", "Kernel", "init.m"}]];
];

(* ═══════════════════════════════════════════════════════════════ *)
(* ③ Define 23 LLMTool (wrapping WolframQFT functions as MCP tools) *)
(* ═══════════════════════════════════════════════════════════════ *)

(* --- Math (8) --- *)

wlEvaluateTool = LLMTool[<|
    "Name" -> "wolfram_evaluate",
    "DisplayName" -> "Wolfram Evaluate (QFT)",
    "Description" -> "Execute arbitrary Wolfram Language code. Security: 3-tier sandbox (permissive/moderate/strict). Results cached (LRU, <1ms repeat).",
    "Parameters" -> {
        "code" -> <|"Interpreter" -> "String", "Help" -> "Wolfram Language code to evaluate", "Required" -> True|>,
        "timeout" -> <|"Interpreter" -> "Integer", "Help" -> "Timeout seconds (default 60)", "Required" -> False|>,
        "form" -> <|"Interpreter" -> "String", "Help" -> "OutputForm (default) / InputForm / TeXForm / CForm", "Required" -> False|>
    },
    "Function" -> Function[args, Wolfram`AgentTools`Common`catchTop[
        WolframQFT`Common`safeEval[Lookup[args, "code", ""], Lookup[args, "form", "OutputForm"], Lookup[args, "timeout", 60]]
    ], HoldAllComplete],
    "Options" -> {}, "LLMPacletVersion" -> "2.2.6"
|>];

wlSolveTool = LLMTool[<|
    "Name" -> "wolfram_solve", "DisplayName" -> "Wolfram Solve",
    "Description" -> "Solve equations. Methods: symbolic (Solve), numeric (NSolve), differential (DSolve), numeric_diff (NDSolve).",
    "Parameters" -> {
        "equations" -> <|"Interpreter" -> "String", "Help" -> "Equations comma-separated, e.g. \"x^2-3x+2==0\"", "Required" -> True|>,
        "variables" -> <|"Interpreter" -> "String", "Help" -> "Variables comma-separated, e.g. \"x, y\"", "Required" -> True|>,
        "method" -> <|"Interpreter" -> "String", "Help" -> "symbolic / numeric / differential / numeric_diff (default symbolic)", "Required" -> False|>,
        "timeout" -> <|"Interpreter" -> "Integer", "Help" -> "Timeout seconds (default 120)", "Required" -> False|>
    },
    "Function" -> Function[args, Wolfram`AgentTools`Common`catchTop[
        WolframQFT`MathTools`wolframSolve[Lookup[args, "equations", ""], Lookup[args, "variables", ""], Lookup[args, "method", "symbolic"], Lookup[args, "timeout", 120]]
    ], HoldAllComplete],
    "Options" -> {}, "LLMPacletVersion" -> "2.2.6"
|>];

wlIntegrateTool = LLMTool[<|
    "Name" -> "wolfram_integrate", "DisplayName" -> "Wolfram Integrate",
    "Description" -> "Symbolic definite/indefinite integration. Supports multi-dimensional integrals. LRU cached.",
    "Parameters" -> {
        "expr" -> <|"Interpreter" -> "String", "Help" -> "Integrand, e.g. \"Exp[-x^2]\"", "Required" -> True|>,
        "var" -> <|"Interpreter" -> "String", "Help" -> "Variable(s), e.g. \"x\" or \"x, y\"", "Required" -> True|>,
        "limits" -> <|"Interpreter" -> "String", "Help" -> "Limits e.g. \"{x,0,Infinity}\". Empty = indefinite.", "Required" -> False|>,
        "timeout" -> <|"Interpreter" -> "Integer", "Help" -> "Timeout seconds (default 180)", "Required" -> False|>
    },
    "Function" -> Function[args, Wolfram`AgentTools`Common`catchTop[
        WolframQFT`MathTools`wolframIntegrate[Lookup[args, "expr", ""], Lookup[args, "var", ""], Lookup[args, "limits", ""], Lookup[args, "timeout", 180]]
    ], HoldAllComplete],
    "Options" -> {}, "LLMPacletVersion" -> "2.2.6"
|>];

wlDifferentiateTool = LLMTool[<|
    "Name" -> "wolfram_differentiate", "DisplayName" -> "Wolfram Differentiate",
    "Description" -> "Compute derivatives. Supports higher-order and partial derivatives.",
    "Parameters" -> {
        "expr" -> <|"Interpreter" -> "String", "Help" -> "Expression, e.g. \"Sin[x^2]\"", "Required" -> True|>,
        "var" -> <|"Interpreter" -> "String", "Help" -> "Variable, e.g. \"x\"", "Required" -> True|>,
        "order" -> <|"Interpreter" -> "Integer", "Help" -> "Derivative order (default 1)", "Required" -> False|>,
        "timeout" -> <|"Interpreter" -> "Integer", "Help" -> "Timeout seconds (default 60)", "Required" -> False|>
    },
    "Function" -> Function[args, Wolfram`AgentTools`Common`catchTop[
        WolframQFT`MathTools`wolframDifferentiate[Lookup[args, "expr", ""], Lookup[args, "var", ""], Lookup[args, "order", 1], Lookup[args, "timeout", 60]]
    ], HoldAllComplete],
    "Options" -> {}, "LLMPacletVersion" -> "2.2.6"
|>];

wlSimplifyTool = LLMTool[<|
    "Name" -> "wolfram_simplify", "DisplayName" -> "Wolfram Simplify",
    "Description" -> "Simplify expressions. Methods: simplify/fullsimplify/expand/factor/together/apart/trigreduce/trigexpand/powerexpand/complexexpand/refine/auto. Auto mode: iterates Simplify<->FullSimplify until LeafCount converges.",
    "Parameters" -> {
        "expr" -> <|"Interpreter" -> "String", "Help" -> "Expression to simplify", "Required" -> True|>,
        "method" -> <|"Interpreter" -> "String", "Help" -> "simplify / fullsimplify / expand / factor / together / apart / trigreduce / trigexpand / powerexpand / complexexpand / refine / auto (default simplify)", "Required" -> False|>,
        "timeout" -> <|"Interpreter" -> "Integer", "Help" -> "Timeout seconds (default 120)", "Required" -> False|>
    },
    "Function" -> Function[args, Wolfram`AgentTools`Common`catchTop[
        WolframQFT`MathTools`wolframSimplify[Lookup[args, "expr", ""], Lookup[args, "method", "simplify"], Lookup[args, "timeout", 120]]
    ], HoldAllComplete],
    "Options" -> {}, "LLMPacletVersion" -> "2.2.6"
|>];

wlMatrixTool = LLMTool[<|
    "Name" -> "wolfram_matrix", "DisplayName" -> "Wolfram Matrix",
    "Description" -> "Matrix operations: det/inv/eigenvalues/eigenvectors/transpose/rank/nullspace/charpoly/jordan/svd/solve.",
    "Parameters" -> {
        "matrix" -> <|"Interpreter" -> "String", "Help" -> "Matrix, e.g. \"{{1,2},{3,4}}\"", "Required" -> True|>,
        "operation" -> <|"Interpreter" -> "String", "Help" -> "det/inv/eigenvalues/eigenvectors/transpose/rank/nullspace/charpoly/jordan/svd/solve", "Required" -> True|>,
        "vector" -> <|"Interpreter" -> "String", "Help" -> "RHS vector for 'solve', e.g. \"{5,11}\"", "Required" -> False|>,
        "timeout" -> <|"Interpreter" -> "Integer", "Help" -> "Timeout seconds (default 120)", "Required" -> False|>
    },
    "Function" -> Function[args, Wolfram`AgentTools`Common`catchTop[
        WolframQFT`MathTools`wolframMatrix[Lookup[args, "matrix", ""], Lookup[args, "operation", ""], Lookup[args, "vector", ""], Lookup[args, "timeout", 120]]
    ], HoldAllComplete],
    "Options" -> {}, "LLMPacletVersion" -> "2.2.6"
|>];

wlNumericTool = LLMTool[<|
    "Name" -> "wolfram_numeric", "DisplayName" -> "Wolfram Numeric",
    "Description" -> "Numerical computation: nintegrate (NIntegrate), nsum (NSum), findroot (FindRoot), nminimize (NMinimize), nmaximize (NMaximize), nlimit (NLimit).",
    "Parameters" -> {
        "operation" -> <|"Interpreter" -> "String", "Help" -> "nintegrate / nsum / findroot / nminimize / nmaximize / nlimit", "Required" -> True|>,
        "expr" -> <|"Interpreter" -> "String", "Help" -> "Expression or equation", "Required" -> True|>,
        "range" -> <|"Interpreter" -> "String", "Help" -> "Range/guess, e.g. \"{x,0,Infinity}\" for nintegrate", "Required" -> False|>,
        "opts" -> <|"Interpreter" -> "String", "Help" -> "Extra options list (default \"{}\")", "Required" -> False|>,
        "timeout" -> <|"Interpreter" -> "Integer", "Help" -> "Timeout seconds (default 180)", "Required" -> False|>
    },
    "Function" -> Function[args, Wolfram`AgentTools`Common`catchTop[
        WolframQFT`MathTools`wolframNumeric[Lookup[args, "operation", ""], Lookup[args, "expr", ""], Lookup[args, "range", ""], Lookup[args, "opts", "{}"], Lookup[args, "timeout", 180]]
    ], HoldAllComplete],
    "Options" -> {}, "LLMPacletVersion" -> "2.2.6"
|>];

wlAssumeTool = LLMTool[<|
    "Name" -> "wolfram_assume", "DisplayName" -> "Wolfram Assume",
    "Description" -> "Manage $Assumptions. Actions: set (replace), add (append), clear (reset), view (show). set/add auto-clear cache.",
    "Parameters" -> {
        "action" -> <|"Interpreter" -> "String", "Help" -> "set / add / clear / view", "Required" -> True|>,
        "arg" -> <|"Interpreter" -> "String", "Help" -> "Assumption e.g. \"x > 0\" (for set/add)", "Required" -> False|>
    },
    "Function" -> Function[args, Wolfram`AgentTools`Common`catchTop[
        WolframQFT`MathTools`wolframAssume[Lookup[args, "action", ""], Lookup[args, "arg", ""]]
    ], HoldAllComplete],
    "Options" -> {}, "LLMPacletVersion" -> "2.2.6"
|>];

(* --- Plot (3) --- *)

wlPlotTool = LLMTool[<|
    "Name" -> "wolfram_plot", "DisplayName" -> "Wolfram 2D Plot",
    "Description" -> "Generate 2D function plot. Returns base64 PNG.",
    "Parameters" -> {
        "function" -> <|"Interpreter" -> "String", "Help" -> "Function of x, e.g. \"Sin[x]\"", "Required" -> True|>,
        "range" -> <|"Interpreter" -> "String", "Help" -> "Range, e.g. \"{x, -Pi, Pi}\"", "Required" -> True|>,
        "width" -> <|"Interpreter" -> "Integer", "Help" -> "Width px (default 600)", "Required" -> False|>,
        "height" -> <|"Interpreter" -> "Integer", "Help" -> "Height px (default 400)", "Required" -> False|>
    },
    "Function" -> Function[args, Wolfram`AgentTools`Common`catchTop[
        WolframQFT`PlotTools`wolframPlot[Lookup[args, "function", ""], Lookup[args, "range", ""], Lookup[args, "width", 600], Lookup[args, "height", 400]]
    ], HoldAllComplete],
    "Options" -> {}, "LLMPacletVersion" -> "2.2.6"
|>];

wlPlot3DTool = LLMTool[<|
    "Name" -> "wolfram_plot3d", "DisplayName" -> "Wolfram 3D Plot",
    "Description" -> "Generate 3D surface plot. Returns base64 PNG.",
    "Parameters" -> {
        "function" -> <|"Interpreter" -> "String", "Help" -> "Function of x,y, e.g. \"Sin[x*y]\"", "Required" -> True|>,
        "range" -> <|"Interpreter" -> "String", "Help" -> "Ranges, e.g. \"{x,-Pi,Pi}, {y,-Pi,Pi}\"", "Required" -> True|>,
        "width" -> <|"Interpreter" -> "Integer", "Help" -> "Width px (default 600)", "Required" -> False|>,
        "height" -> <|"Interpreter" -> "Integer", "Help" -> "Height px (default 500)", "Required" -> False|>
    },
    "Function" -> Function[args, Wolfram`AgentTools`Common`catchTop[
        WolframQFT`PlotTools`wolframPlot3D[Lookup[args, "function", ""], Lookup[args, "range", ""], Lookup[args, "width", 600], Lookup[args, "height", 500]]
    ], HoldAllComplete],
    "Options" -> {}, "LLMPacletVersion" -> "2.2.6"
|>];

wlParametricPlotTool = LLMTool[<|
    "Name" -> "wolfram_parametric_plot", "DisplayName" -> "Wolfram Parametric Plot",
    "Description" -> "Generate parametric curve plot. Returns base64 PNG.",
    "Parameters" -> {
        "x_expr" -> <|"Interpreter" -> "String", "Help" -> "x(t), e.g. \"Cos[t]\"", "Required" -> True|>,
        "y_expr" -> <|"Interpreter" -> "String", "Help" -> "y(t), e.g. \"Sin[t]\"", "Required" -> True|>,
        "range" -> <|"Interpreter" -> "String", "Help" -> "Parameter range, e.g. \"{t, 0, 2*Pi}\"", "Required" -> True|>,
        "width" -> <|"Interpreter" -> "Integer", "Help" -> "Width px (default 600)", "Required" -> False|>,
        "height" -> <|"Interpreter" -> "Integer", "Help" -> "Height px (default 400)", "Required" -> False|>
    },
    "Function" -> Function[args, Wolfram`AgentTools`Common`catchTop[
        WolframQFT`PlotTools`wolframParametricPlot[Lookup[args, "x_expr", ""], Lookup[args, "y_expr", ""], Lookup[args, "range", ""], Lookup[args, "width", 600], Lookup[args, "height", 400]]
    ], HoldAllComplete],
    "Options" -> {}, "LLMPacletVersion" -> "2.2.6"
|>];

(* --- Physics (10) --- *)

physLoadPkgTool = LLMTool[<|
    "Name" -> "physics_load_package", "DisplayName" -> "Load Physics Package",
    "Description" -> "Load a physics package: FeynCalc, FeynArts, FeynHelpers, PackageX, FIRE, xAct.",
    "Parameters" -> {
        "name" -> <|"Interpreter" -> "String", "Help" -> "FeynCalc / FeynArts / FeynHelpers / PackageX / FIRE / xAct", "Required" -> True|>
    },
    "Function" -> Function[args, Wolfram`AgentTools`Common`catchTop[
        WolframQFT`Common`loadPackage[Lookup[args, "name", ""]]
    ], HoldAllComplete],
    "Options" -> {}, "LLMPacletVersion" -> "2.2.6"
|>];

physFeyncalcAmpTool = LLMTool[<|
    "Name" -> "physics_feyncalc_amplitude", "DisplayName" -> "FeynCalc Amplitude",
    "Description" -> "Compute QFT scattering amplitudes via FeynCalc. Auto-loads FeynCalc.",
    "Parameters" -> {
        "code" -> <|"Interpreter" -> "String", "Help" -> "FeynCalc code, e.g. \"SpinorUBar[p1,m].GA[mu].SpinorU[p2,m]\"", "Required" -> True|>,
        "timeout" -> <|"Interpreter" -> "Integer", "Help" -> "Timeout seconds (default 120)", "Required" -> False|>
    },
    "Function" -> Function[args, Wolfram`AgentTools`Common`catchTop[
        WolframQFT`PhysicsTools`feyncalcAmplitude[Lookup[args, "code", ""], Lookup[args, "timeout", 120]]
    ], HoldAllComplete],
    "Options" -> {}, "LLMPacletVersion" -> "2.2.6"
|>];

physDiracTraceTool = LLMTool[<|
    "Name" -> "physics_dirac_trace", "DisplayName" -> "Dirac Trace",
    "Description" -> "Compute Dirac gamma matrix traces via FeynCalc. Auto-loads FeynCalc.",
    "Parameters" -> {
        "expr" -> <|"Interpreter" -> "String", "Help" -> "Dirac expression, e.g. \"GA[mu,nu,rho,sigma]\"", "Required" -> True|>
    },
    "Function" -> Function[args, Wolfram`AgentTools`Common`catchTop[
        WolframQFT`PhysicsTools`diracTrace[Lookup[args, "expr", ""]]
    ], HoldAllComplete],
    "Options" -> {}, "LLMPacletVersion" -> "2.2.6"
|>];

physColorFactorTool = LLMTool[<|
    "Name" -> "physics_color_factor", "DisplayName" -> "Color Factor",
    "Description" -> "Compute SU(N) color factors via FeynCalc SUNSimplify. Auto-loads FeynCalc.",
    "Parameters" -> {
        "expr" -> <|"Interpreter" -> "String", "Help" -> "Color expr, e.g. \"SUNT[a].SUNT[b].SUNT[c]\"", "Required" -> True|>
    },
    "Function" -> Function[args, Wolfram`AgentTools`Common`catchTop[
        WolframQFT`PhysicsTools`colorFactor[Lookup[args, "expr", ""]]
    ], HoldAllComplete],
    "Options" -> {}, "LLMPacletVersion" -> "2.2.6"
|>];

physLoopIntTool = LLMTool[<|
    "Name" -> "physics_loop_integral", "DisplayName" -> "Loop Integral",
    "Description" -> "Reduce loop integrals: tid (tensor decomposition) or pavereduce (Passarino-Veltman). Auto-loads FeynCalc.",
    "Parameters" -> {
        "expr" -> <|"Interpreter" -> "String", "Help" -> "Loop integral expression in FeynCalc notation", "Required" -> True|>,
        "method" -> <|"Interpreter" -> "String", "Help" -> "tid (default) or pavereduce", "Required" -> False|>
    },
    "Function" -> Function[args, Wolfram`AgentTools`Common`catchTop[
        WolframQFT`PhysicsTools`loopIntegral[Lookup[args, "expr", ""], Lookup[args, "method", "tid"]]
    ], HoldAllComplete],
    "Options" -> {}, "LLMPacletVersion" -> "2.2.6"
|>];

physFeynDiagramTool = LLMTool[<|
    "Name" -> "physics_feynman_diagram", "DisplayName" -> "Feynman Diagram",
    "Description" -> "Generate Feynman diagrams via FeynArts. Built-in: compton, bhabha, moller, pair_annihilation, gg_scatter. Or custom FeynArts code. Returns base64 PNG.",
    "Parameters" -> {
        "process" -> <|"Interpreter" -> "String", "Help" -> "compton / bhabha / moller / pair_annihilation / gg_scatter (empty for custom code)", "Required" -> False|>,
        "code" -> <|"Interpreter" -> "String", "Help" -> "Custom FeynArts code (if process empty)", "Required" -> False|>,
        "model" -> <|"Interpreter" -> "String", "Help" -> "QED (default) / QCD / SM", "Required" -> False|>
    },
    "Function" -> Function[args, Wolfram`AgentTools`Common`catchTop[
        WolframQFT`PhysicsTools`feynmanDiagram[Lookup[args, "process", ""], Lookup[args, "code", ""], Lookup[args, "model", "QED"]]
    ], HoldAllComplete],
    "Options" -> {}, "LLMPacletVersion" -> "2.2.6"
|>];

physPackageXTool = LLMTool[<|
    "Name" -> "physics_package_x", "DisplayName" -> "Package-X",
    "Description" -> "Evaluate one-loop Passarino-Veltman integrals analytically via Package-X. Returns PaVe functions + UV 1/epsilon poles.",
    "Parameters" -> {
        "expr" -> <|"Interpreter" -> "String", "Help" -> "Package-X expression", "Required" -> True|>
    },
    "Function" -> Function[args, Wolfram`AgentTools`Common`catchTop[
        WolframQFT`PhysicsTools`packageXEvaluate[Lookup[args, "expr", ""]]
    ], HoldAllComplete],
    "Options" -> {}, "LLMPacletVersion" -> "2.2.6"
|>];

physFIREreduceTool = LLMTool[<|
    "Name" -> "physics_fire_reduce", "DisplayName" -> "FIRE IBP Reduction",
    "Description" -> "Integration-By-Parts reduction of multi-loop integrals via FIRE. Returns master integrals.",
    "Parameters" -> {
        "sectors" -> <|"Interpreter" -> "String", "Help" -> "Sector list, e.g. \"{1,1,1,1,1}\"", "Required" -> True|>,
        "propagators" -> <|"Interpreter" -> "String", "Help" -> "Propagators comma-separated", "Required" -> True|>,
        "loop_vars" -> <|"Interpreter" -> "String", "Help" -> "Loop momenta, e.g. \"k\" or \"k,l\"", "Required" -> True|>
    },
    "Function" -> Function[args, Wolfram`AgentTools`Common`catchTop[
        WolframQFT`PhysicsTools`fireReduce[Lookup[args, "sectors", ""], Lookup[args, "propagators", ""], Lookup[args, "loop_vars", ""]]
    ], HoldAllComplete],
    "Options" -> {}, "LLMPacletVersion" -> "2.2.6"
|>];

physXActTool = LLMTool[<|
    "Name" -> "physics_xact_tensor", "DisplayName" -> "xAct Tensor Algebra",
    "Description" -> "Tensor algebra on curved manifolds: RicciCD, RiemannCD, EinsteinCD, WeylCD, covariant derivative CD, variational derivative VarD.",
    "Parameters" -> {
        "code" -> <|"Interpreter" -> "String", "Help" -> "xAct code, e.g. \"RicciCD[-a,-b]\" or \"VarD[g[-a,-b],CD][Sqrt[Detg[]]RicciScalarCD[]]\"", "Required" -> True|>
    },
    "Function" -> Function[args, Wolfram`AgentTools`Common`catchTop[
        WolframQFT`PhysicsTools`xActTensor[Lookup[args, "code", ""]]
    ], HoldAllComplete],
    "Options" -> {}, "LLMPacletVersion" -> "2.2.6"
|>];

physFeynhelpersTool = LLMTool[<|
    "Name" -> "physics_feynhelpers_convert", "DisplayName" -> "FeynCalc<->PackageX Bridge",
    "Description" -> "Convert loop integrals: to_packagex (FCFI, FeynCalc->PackageX) or to_feyncalc (FCPI, PackageX->FeynCalc).",
    "Parameters" -> {
        "expr" -> <|"Interpreter" -> "String", "Help" -> "Integral expression to convert", "Required" -> True|>,
        "direction" -> <|"Interpreter" -> "String", "Help" -> "to_packagex (default) or to_feyncalc", "Required" -> False|>
    },
    "Function" -> Function[args, Wolfram`AgentTools`Common`catchTop[
        WolframQFT`PhysicsTools`feynhelpersConvert[Lookup[args, "expr", ""], Lookup[args, "direction", "to_packagex"]]
    ], HoldAllComplete],
    "Options" -> {}, "LLMPacletVersion" -> "2.2.6"
|>];

(* --- Session (2) --- *)

wlSessionInfoTool = LLMTool[<|
    "Name" -> "wolfram_session_info", "DisplayName" -> "Session Info",
    "Description" -> "Kernel status: Mathematica version, loaded physics packages (with versions), security level, LRU cache statistics.",
    "Parameters" -> {},
    "Function" -> Function[args, Wolfram`AgentTools`Common`catchTop[
        WolframQFT`SessionTools`wolframSessionInfo[]
    ], HoldAllComplete],
    "Options" -> {}, "LLMPacletVersion" -> "2.2.6"
|>];

wlResetKernelTool = LLMTool[<|
    "Name" -> "wolfram_reset_kernel", "DisplayName" -> "Reset Kernel",
    "Description" -> "Reset Mathematica kernel (clear definitions, cache, packages, assumptions). Requires confirm=True. New kernel auto-starts on next call.",
    "Parameters" -> {
        "confirm" -> <|"Interpreter" -> "Boolean", "Help" -> "Must be True to execute (safety guard)", "Required" -> True|>
    },
    "Function" -> Function[args, Wolfram`AgentTools`Common`catchTop[
        WolframQFT`SessionTools`wolframResetKernel[Lookup[args, "confirm", False]]
    ], HoldAllComplete],
    "Options" -> {}, "LLMPacletVersion" -> "2.2.6"
|>];

(* ═══════════════════════════════════════════════════════════════ *)
(* ④ Assemble all 30 tools (7 built-in + 23 custom) *)
(* ═══════════════════════════════════════════════════════════════ *)

allCustomTools = {
    wlEvaluateTool, wlSolveTool, wlIntegrateTool, wlDifferentiateTool,
    wlSimplifyTool, wlMatrixTool, wlNumericTool, wlAssumeTool,
    wlPlotTool, wlPlot3DTool, wlParametricPlotTool,
    physLoadPkgTool, physFeyncalcAmpTool, physDiracTraceTool,
    physColorFactorTool, physLoopIntTool, physFeynDiagramTool,
    physPackageXTool, physFIREreduceTool, physXActTool, physFeynhelpersTool,
    wlSessionInfoTool, wlResetKernelTool
};

(* 提取官方 7 个高级内置工具的对象 (修正：强制使用绝对上下文防止报错) *)
builtInTools = Values @ KeyTake[Wolfram`AgentTools`$DefaultMCPTools, {
    "WolframLanguageContext", "WolframLanguageEvaluator",
    "ReadNotebook", "WriteNotebook", "SymbolDefinition",
    "CodeInspector", "TestReport"
}];

(* 合并为 30 个工具的终极军火库 *)
finalTools = Join[builtInTools, allCustomTools];

(* ═══════════════════════════════════════════════════════════════ *)
(* ⑤ 注入工具并强行启动定制 MCP 服务器 *)
(* ═══════════════════════════════════════════════════════════════ *)

(* 1. 通过 First 剥离外壳，抓取关联数据 *)
baseAssoc = First[MCPServerObject["WolframLanguage"]];

(* 2. 修正：切勿直接覆盖赋值！使用 Append 构建全新关联字典，避免 Tag Protected 报错 *)
newEvaluator = <|
    "Tools" -> finalTools,
    "MCPPrompts" -> baseAssoc["LLMEvaluator", "MCPPrompts"]
|>;
customAssoc = Append[baseAssoc, "LLMEvaluator" -> newEvaluator];

(* 3. 重新包装为量身定制的 MCP 服务器对象 *)
customServer = MCPServerObject[customAssoc];

(* 4. 终极启动 *)
StartMCPServer[customServer];
