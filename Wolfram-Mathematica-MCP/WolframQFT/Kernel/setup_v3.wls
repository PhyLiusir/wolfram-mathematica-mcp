
(* WolframQFT MCP Server Setup — v3.1
   Registers all 23 WolframQFT tools + WolframLanguage built-ins.
   Run this in an interactive Mathematica session.
   Requires: Wolfram/AgentTools paclet installed. *)

Needs["Wolfram`AgentTools`"];
Needs["Wolfram`AgentTools`CreateMCPServer`"];
Needs["WolframQFT`"];

(* Check FeynArts availability *)
feynArtsAvailable = FindFile["FeynArts`"] =!= $Failed || 
   (StringQ[Environment["FEYNARTS_DIR"]] && FileExistsQ[
     FileNameJoin[{Environment["FEYNARTS_DIR"], "FeynArts", "Kernel", "init.m"}]]);
Print["FeynArts available: ", feynArtsAvailable];

(* ══════════════════════════════════════════════════════════════════ *)
(* Math Tools — 8 tools *)
mathTools = {
  LLMTool[
    {"wolfram_evaluate",
     "Execute arbitrary Wolfram Language code. Security: 3-tier sandbox (permissive/moderate/strict). Results cached (LRU, <1ms repeat)."},
    {"code" -> <|"Interpreter" -> "String", "Required" -> True,
        "Help" -> "Wolfram Language code to evaluate"|>,
     "timeout" -> <|"Interpreter" -> "Integer", "Required" -> False,
        "Help" -> "Timeout seconds (default 60)"|>,
     "form" -> <|"Interpreter" -> "String", "Required" -> False,
        "Help" -> "OutputForm (default) / InputForm / TeXForm / CForm"|>},
    WolframQFT`MathTools`wolframEvaluate[#code, Replace[#timeout, Except[_Integer]->60], 
      Replace[#form, Except[_String]->"OutputForm"]] &
  ],
  LLMTool[
    {"wolfram_solve",
     "Solve equations. Methods: symbolic (Solve), numeric (NSolve), differential (DSolve), numeric_diff (NDSolve)."},
    {"equations" -> <|"Interpreter" -> "String", "Required" -> True,
        "Help" -> "Equations comma-separated, e.g. \"x^2-3x+2==0\""|>,
     "variables" -> <|"Interpreter" -> "String", "Required" -> True,
        "Help" -> "Variables comma-separated, e.g. \"x, y\""|>,
     "method" -> <|"Interpreter" -> "String", "Required" -> False,
        "Help" -> "symbolic / numeric / differential / numeric_diff (default symbolic)"|>,
     "timeout" -> <|"Interpreter" -> "Integer", "Required" -> False,
        "Help" -> "Timeout seconds (default 120)"|>},
    WolframQFT`MathTools`wolframSolve[#equations, #variables,
      Replace[#method, Except[_String]->"symbolic"],
      Replace[#timeout, Except[_Integer]->120]] &
  ],
  LLMTool[
    {"wolfram_integrate",
     "Symbolic definite/indefinite integration. Supports multi-dimensional integrals. LRU cached."},
    {"expr" -> <|"Interpreter" -> "String", "Required" -> True,
        "Help" -> "Integrand, e.g. \"Exp[-x^2]\""|>,
     "var" -> <|"Interpreter" -> "String", "Required" -> True,
        "Help" -> "Variable(s), e.g. \"x\" or \"x, y\""|>,
     "limits" -> <|"Interpreter" -> "String", "Required" -> False,
        "Help" -> "Limits e.g. \"{x,0,Infinity}\". Empty = indefinite."|>,
     "timeout" -> <|"Interpreter" -> "Integer", "Required" -> False,
        "Help" -> "Timeout seconds (default 180)"|>},
    WolframQFT`MathTools`wolframIntegrate[#expr, #var,
      Replace[#limits, Except[_String]->""],
      Replace[#timeout, Except[_Integer]->180]] &
  ],
  LLMTool[
    {"wolfram_differentiate",
     "Compute derivatives. Supports higher-order and partial derivatives."},
    {"expr" -> <|"Interpreter" -> "String", "Required" -> True,
        "Help" -> "Expression, e.g. \"Sin[x^2]\""|>,
     "var" -> <|"Interpreter" -> "String", "Required" -> True,
        "Help" -> "Variable, e.g. \"x\""|>,
     "order" -> <|"Interpreter" -> "Integer", "Required" -> False,
        "Help" -> "Derivative order (default 1)"|>,
     "timeout" -> <|"Interpreter" -> "Integer", "Required" -> False,
        "Help" -> "Timeout seconds (default 60)"|>},
    WolframQFT`MathTools`wolframDifferentiate[#expr, #var,
      Replace[#order, Except[_Integer]->1],
      Replace[#timeout, Except[_Integer]->60]] &
  ],
  LLMTool[
    {"wolfram_simplify",
     "Simplify expressions. Methods: simplify/fullsimplify/expand/factor/together/apart/trigreduce/trigexpand/powerexpand/complexexpand/refine/auto. Auto mode: iterates Simplify<->FullSimplify until LeafCount converges."},
    {"expr" -> <|"Interpreter" -> "String", "Required" -> True,
        "Help" -> "Expression to simplify"|>,
     "method" -> <|"Interpreter" -> "String", "Required" -> False,
        "Help" -> "simplify / fullsimplify / expand / factor / together / apart / trigreduce / trigexpand / powerexpand / complexexpand / refine / auto (default simplify)"|>,
     "timeout" -> <|"Interpreter" -> "Integer", "Required" -> False,
        "Help" -> "Timeout seconds (default 120)"|>},
    WolframQFT`MathTools`wolframSimplify[#expr,
      Replace[#method, Except[_String]->"simplify"],
      Replace[#timeout, Except[_Integer]->120]] &
  ],
  LLMTool[
    {"wolfram_matrix",
     "Matrix operations: det/inv/eigenvalues/eigenvectors/transpose/rank/nullspace/charpoly/jordan/svd/solve."},
    {"matrix" -> <|"Interpreter" -> "String", "Required" -> True,
        "Help" -> "Matrix, e.g. \"{{1,2},{3,4}}\""|>,
     "operation" -> <|"Interpreter" -> "String", "Required" -> True,
        "Help" -> "det/inv/eigenvalues/eigenvectors/transpose/rank/nullspace/charpoly/jordan/svd/solve"|>,
     "vector" -> <|"Interpreter" -> "String", "Required" -> False,
        "Help" -> "RHS vector for 'solve', e.g. \"{5,11}\""|>,
     "timeout" -> <|"Interpreter" -> "Integer", "Required" -> False,
        "Help" -> "Timeout seconds (default 120)"|>},
    WolframQFT`MathTools`wolframMatrix[#matrix, #operation,
      Replace[#vector, Except[_String]->""],
      Replace[#timeout, Except[_Integer]->120]] &
  ],
  LLMTool[
    {"wolfram_numeric",
     "Numerical computation: nintegrate (NIntegrate), nsum (NSum), findroot (FindRoot), nminimize (NMinimize), nmaximize (NMaximize), nlimit (NLimit)."},
    {"operation" -> <|"Interpreter" -> "String", "Required" -> True,
        "Help" -> "nintegrate / nsum / findroot / nminimize / nmaximize / nlimit"|>,
     "expr" -> <|"Interpreter" -> "String", "Required" -> True,
        "Help" -> "Expression or equation"|>,
     "range" -> <|"Interpreter" -> "String", "Required" -> False,
        "Help" -> "Range/guess, e.g. \"{x,0,Infinity}\" for nintegrate"|>,
     "opts" -> <|"Interpreter" -> "String", "Required" -> False,
        "Help" -> "Extra options list (default \"{}\")"|>,
     "timeout" -> <|"Interpreter" -> "Integer", "Required" -> False,
        "Help" -> "Timeout seconds (default 180)"|>},
    WolframQFT`MathTools`wolframNumeric[#operation, #expr,
      Replace[#range, Except[_String]->""],
      Replace[#opts, Except[_String]->"{}"],
      Replace[#timeout, Except[_Integer]->180]] &
  ],
  LLMTool[
    {"wolfram_assume",
     "Manage $Assumptions. Actions: set (replace), add (append), clear (reset), view (show). set/add auto-clear cache."},
    {"action" -> <|"Interpreter" -> "String", "Required" -> True,
        "Help" -> "set / add / clear / view"|>,
     "arg" -> <|"Interpreter" -> "String", "Required" -> False,
        "Help" -> "Assumption e.g. \"x > 0\" (for set/add)"|>},
    WolframQFT`MathTools`wolframAssume[#action,
      Replace[#arg, Except[_String]->""]] &
  ]
};

(* ══════════════════════════════════════════════════════════════════ *)
(* Plot Tools — 3 tools *)
plotTools = {
  LLMTool[
    {"wolfram_plot",
     "Generate 2D function plot. Returns base64 PNG."},
    {"function" -> <|"Interpreter" -> "String", "Required" -> True,
        "Help" -> "Function of x, e.g. \"Sin[x]\""|>,
     "range" -> <|"Interpreter" -> "String", "Required" -> True,
        "Help" -> "Range, e.g. \"{x, -Pi, Pi}\""|>,
     "width" -> <|"Interpreter" -> "Integer", "Required" -> False,
        "Help" -> "Width px (default 600)"|>,
     "height" -> <|"Interpreter" -> "Integer", "Required" -> False,
        "Help" -> "Height px (default 400)"|>},
    WolframQFT`PlotTools`wolframPlot[#function, #range,
      Replace[#width, Except[_Integer]->600],
      Replace[#height, Except[_Integer]->400]] &
  ],
  LLMTool[
    {"wolfram_plot3d",
     "Generate 3D surface plot. Returns base64 PNG."},
    {"function" -> <|"Interpreter" -> "String", "Required" -> True,
        "Help" -> "Function of x,y, e.g. \"Sin[x*y]\""|>,
     "range" -> <|"Interpreter" -> "String", "Required" -> True,
        "Help" -> "Ranges, e.g. \"{x,-Pi,Pi}, {y,-Pi,Pi}\""|>,
     "width" -> <|"Interpreter" -> "Integer", "Required" -> False,
        "Help" -> "Width px (default 600)"|>,
     "height" -> <|"Interpreter" -> "Integer", "Required" -> False,
        "Help" -> "Height px (default 500)"|>},
    WolframQFT`PlotTools`wolframPlot3D[#function, #range,
      Replace[#width, Except[_Integer]->600],
      Replace[#height, Except[_Integer]->500]] &
  ],
  LLMTool[
    {"wolfram_parametric_plot",
     "Generate parametric curve plot. Returns base64 PNG."},
    {"x_expr" -> <|"Interpreter" -> "String", "Required" -> True,
        "Help" -> "x(t), e.g. \"Cos[t]\""|>,
     "y_expr" -> <|"Interpreter" -> "String", "Required" -> True,
        "Help" -> "y(t), e.g. \"Sin[t]\""|>,
     "range" -> <|"Interpreter" -> "String", "Required" -> True,
        "Help" -> "Parameter range, e.g. \"{t, 0, 2*Pi}\""|>,
     "width" -> <|"Interpreter" -> "Integer", "Required" -> False,
        "Help" -> "Width px (default 600)"|>,
     "height" -> <|"Interpreter" -> "Integer", "Required" -> False,
        "Help" -> "Height px (default 400)"|>},
    WolframQFT`PlotTools`wolframParametricPlot[#x_expr, #y_expr, #range,
      Replace[#width, Except[_Integer]->600],
      Replace[#height, Except[_Integer]->400]] &
  ]
};

(* ══════════════════════════════════════════════════════════════════ *)
(* Physics Tools — 10 tools (v3.1: new feynman_diagram) *)
physicsTools = {
  LLMTool[
    {"physics_load_package",
     "Load a physics package: FeynCalc, FeynArts, FeynHelpers, PackageX, FIRE, xAct."},
    {"name" -> <|"Interpreter" -> "String", "Required" -> True,
        "Help" -> "FeynCalc / FeynArts / FeynHelpers / PackageX / FIRE / xAct"|>},
    WolframQFT`PhysicsTools`physicsLoadPackage[#name] &
  ],
  LLMTool[
    {"physics_feyncalc_amplitude",
     "Compute QFT scattering amplitudes via FeynCalc. Auto-loads FeynCalc."},
    {"code" -> <|"Interpreter" -> "String", "Required" -> True,
        "Help" -> "FeynCalc code, e.g. \"SpinorUBar[p1,m].GA[mu].SpinorU[p2,m]\""|>,
     "timeout" -> <|"Interpreter" -> "Integer", "Required" -> False,
        "Help" -> "Timeout seconds (default 120)"|>},
    WolframQFT`PhysicsTools`feyncalcAmplitude[#code,
      Replace[#timeout, Except[_Integer]->120]] &
  ],
  LLMTool[
    {"physics_dirac_trace",
     "Compute Dirac gamma matrix traces via FeynCalc. Auto-loads FeynCalc."},
    {"expr" -> <|"Interpreter" -> "String", "Required" -> True,
        "Help" -> "Dirac expression, e.g. \"GA[mu,nu,rho,sigma]\""|>},
    WolframQFT`PhysicsTools`diracTrace[#expr] &
  ],
  LLMTool[
    {"physics_color_factor",
     "Compute SU(N) color factors via FeynCalc SUNSimplify. Auto-loads FeynCalc."},
    {"expr" -> <|"Interpreter" -> "String", "Required" -> True,
        "Help" -> "Color expr, e.g. \"SUNT[a].SUNT[b].SUNT[c]\""|>},
    WolframQFT`PhysicsTools`colorFactor[#expr] &
  ],
  LLMTool[
    {"physics_loop_integral",
     "Reduce loop integrals: tid (tensor decomposition) or pavereduce (Passarino-Veltman). Auto-loads FeynCalc."},
    {"expr" -> <|"Interpreter" -> "String", "Required" -> True,
        "Help" -> "Loop integral expression in FeynCalc notation"|>,
     "method" -> <|"Interpreter" -> "String", "Required" -> False,
        "Help" -> "tid (default) or pavereduce"|>},
    WolframQFT`PhysicsTools`loopIntegral[#expr,
      Replace[#method, Except[_String]->"tid"]] &
  ],
  LLMTool[
    {"physics_feynman_diagram",
     "Generate Feynman diagrams via FeynArts. Specify incoming/outgoing particles by name (electron, positron, photon, gluon, higgs, etc.) or raw FeynArts field codes like \"F[2,{1}]\". models: SM/SMQCD/MSSM/QED/QCD. loopOrder: 0-2. Returns embedded base64 PNG/PDF."},
    {"incoming" -> <|"Interpreter" -> {"String"}, "Required" -> True,
        "Help" -> "Incoming particle names, e.g. {\"electron\",\"positron\"}"|>,
     "outgoing" -> <|"Interpreter" -> {"String"}, "Required" -> True,
        "Help" -> "Outgoing particle names, e.g. {\"muon\",\"antimuon\"}"|>,
     "model" -> <|"Interpreter" -> "String", "Required" -> False,
        "Help" -> "FeynArts model: SM (default), SMQCD, MSSM, QED, QCD"|>,
     "loopOrder" -> <|"Interpreter" -> "Integer", "Required" -> False,
        "Help" -> "Number of loops: 0 (tree level, default) to 2"|>,
     "excludeParticles" -> <|"Interpreter" -> {"String"}, "Required" -> False,
        "Help" -> "Particle names to exclude from internal lines"|>,
     "imageFormat" -> <|"Interpreter" -> "String", "Required" -> False,
        "Help" -> "png (default, shows inline) or pdf"|>},
    WolframQFT`PhysicsTools`feynmanDiagram[
      #incoming, #outgoing,
      Replace[#model,            Except[_String]  -> "SM"],
      Replace[#loopOrder,        Except[_Integer] -> 0],
      Replace[#excludeParticles, Except[_List]     -> {}],
      Replace[#imageFormat,      Except[_String]   -> "png"]
    ] &
  ],
  LLMTool[
    {"physics_package_x",
     "Evaluate one-loop Passarino-Veltman integrals analytically via Package-X. Returns PaVe functions + UV 1/epsilon poles."},
    {"expr" -> <|"Interpreter" -> "String", "Required" -> True,
        "Help" -> "Package-X expression"|>},
    WolframQFT`PhysicsTools`packageXEvaluate[#expr] &
  ],
  LLMTool[
    {"physics_fire_reduce",
     "Integration-By-Parts reduction of multi-loop integrals via FIRE. Returns master integrals."},
    {"sectors" -> <|"Interpreter" -> "String", "Required" -> True,
        "Help" -> "Sector list, e.g. \"{1,1,1,1,1}\""|>,
     "propagators" -> <|"Interpreter" -> "String", "Required" -> True,
        "Help" -> "Propagators comma-separated"|>,
     "loop_vars" -> <|"Interpreter" -> "String", "Required" -> True,
        "Help" -> "Loop momenta, e.g. \"k\" or \"k,l\""|>},
    WolframQFT`PhysicsTools`fireReduce[#sectors, #propagators, #loop_vars] &
  ],
  LLMTool[
    {"physics_xact_tensor",
     "Tensor algebra on curved manifolds: RicciCD, RiemannCD, EinsteinCD, WeylCD, covariant derivative CD, variational derivative VarD."},
    {"code" -> <|"Interpreter" -> "String", "Required" -> True,
        "Help" -> "xAct code, e.g. \"RicciCD[-a,-b]\" or \"VarD[g[-a,-b],CD][Sqrt[Detg[]]RicciScalarCD[]]\""|>},
    WolframQFT`PhysicsTools`xActTensor[#code] &
  ],
  LLMTool[
    {"physics_feynhelpers_convert",
     "Convert loop integrals: to_packagex (FCFI, FeynCalc->PackageX) or to_feyncalc (FCPI, PackageX->FeynCalc)."},
    {"expr" -> <|"Interpreter" -> "String", "Required" -> True,
        "Help" -> "Integral expression to convert"|>,
     "direction" -> <|"Interpreter" -> "String", "Required" -> False,
        "Help" -> "to_packagex (default) or to_feyncalc"|>},
    WolframQFT`PhysicsTools`feynhelpersConvert[#expr,
      Replace[#direction, Except[_String]->"to_packagex"]] &
  ]
};

(* ══════════════════════════════════════════════════════════════════ *)
(* Session Tools — 2 tools *)
sessionTools = {
  LLMTool[
    {"wolfram_session_info",
     "Kernel status: Mathematica version, loaded physics packages (with versions), security level, LRU cache statistics."},
    {},
    WolframQFT`SessionTools`wolframSessionInfo[] &
  ],
  LLMTool[
    {"wolfram_reset_kernel",
     "Reset Mathematica kernel (clear definitions, cache, packages, assumptions). Requires confirm=True. New kernel auto-starts on next call."},
    {"confirm" -> <|"Interpreter" -> "Boolean", "Required" -> True,
        "Help" -> "Must be True to execute (safety guard)"|>},
    WolframQFT`SessionTools`wolframResetKernel[#confirm] &
  ]
};

(* ══════════════════════════════════════════════════════════════════ *)
(* Assemble ALL tools *)
allTools = Join[
  mathTools,
  plotTools,
  physicsTools,
  sessionTools
];

Print["Total WolframQFT tools: ", Length[allTools]];

(* ══════════════════════════════════════════════════════════════════ *)
(* Create MCP Server *)
result = CreateMCPServer["WolframQFT",
  <| "Tools" -> allTools |>,
  OverwriteTarget -> True
];

If[MCPServerObjectQ[result],
  Print["SUCCESS: WolframQFT MCP server registered."];
  Print["Tools registered: ", Length[result["ToolNames"]]];
  Print["Tool names: ", result["ToolNames"]],
  Print["FAILED: ", result]
];

result
