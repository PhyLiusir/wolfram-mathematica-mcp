(* WolframQFT Math Tools — v2.0
   Symbolic construction + timeouts + auto-simplify + numeric + assumptions *)
BeginPackage["WolframQFT`MathTools`"];

wolframEvaluate::usage = "wolframEvaluate[code, timeout, form] — execute arbitrary WL code.";
wolframSolve::usage = "wolframSolve[eqs, vars, method, timeout] — solve equations.";
wolframIntegrate::usage = "wolframIntegrate[expr, var, limits, timeout] — integrate.";
wolframDifferentiate::usage = "wolframDifferentiate[expr, var, order, timeout] — differentiate.";
wolframSimplify::usage = "wolframSimplify[expr, method, timeout] — simplify (method: simplify|fullsimplify|expand|factor|together|apart|trigreduce|trigexpand|powerexpand|complexexpand|refine|auto).";
wolframMatrix::usage = "wolframMatrix[matrix, operation, vector, timeout] — matrix operations.";
wolframNumeric::usage = "wolframNumeric[operation, expr, range, opts, timeout] — numeric computation (nintegrate|nsum|findroot|nminimize|nmaximize|nlimit).";
wolframAssume::usage = "wolframAssume[action, arg] — manage $Assumptions (set|add|clear|view).";

Begin["`Private`"];

(* ── Helper ─────────────────────────────────────────────────── *)
parseHold[s_String] := ToExpression[s, InputForm, Hold];

(* ═══════════════════════════════════════════════════════════════ *)
(* wolfram_evaluate *)
(* ═══════════════════════════════════════════════════════════════ *)
wolframEvaluate[code_String, timeout_:60, form_:"OutputForm"] :=
    WolframQFT`Common`safeEval[code, form, Min[timeout, 300]];

(* ═══════════════════════════════════════════════════════════════ *)
(* wolfram_solve — inlined cache + timeout pattern *)
(* ═══════════════════════════════════════════════════════════════ *)
wolframSolve[equations_String, variables_String, method_:"symbolic", timeout_:120] :=
    Module[{eqHold, varHold, fn, key, cached, result, start, elapsed, maxTime},

        (* Build expression symbolically *)
        eqHold = parseHold["{" <> equations <> "}"];
        varHold = parseHold["{" <> variables <> "}"];

        fn = Switch[method,
            "symbolic",     Hold[Solve][eqHold, varHold],
            "numeric",      Hold[NSolve][eqHold, varHold],
            "differential", Hold[DSolve][eqHold, varHold, x],
            "numeric_diff", Hold[NDSolve][eqHold, varHold, {x, 0, 10}],
            _,              Return["Unknown method: " <> method <>
                                 ". Use: symbolic, numeric, differential, numeric_diff."]
        ];

        (* Cache check *)
        key = WolframQFT`Common`cacheKey["wolframSolve", equations, variables, method];
        cached = WolframQFT`Common`cacheGet[key];
        If[cached =!= Missing["Key", key],
            Return[cached]
        ];

        (* Compute *)
        maxTime = Min[timeout, 300];
        start = AbsoluteTime[];
        result = Check[
            TimeConstrained[ReleaseHold[fn], maxTime,
                "[TIMEOUT] wolframSolve exceeded " <> ToString[maxTime] <> "s."],
            "[ERROR] wolframSolve failed.",
            {General::all}
        ];
        elapsed = Round[AbsoluteTime[] - start, 0.01];

        result = ToString[result, OutputForm];
        result = result <> "\n[wolframSolve elapsed: " <> ToString[elapsed] <> "s]";

        (* Cache *)
        If[!StringContainsQ[result, "[TIMEOUT]"] && !StringContainsQ[result, "[ERROR]"],
            WolframQFT`Common`cachePut[key, result]
        ];

        result
    ];

(* ═══════════════════════════════════════════════════════════════ *)
(* wolfram_integrate *)
(* ═══════════════════════════════════════════════════════════════ *)
wolframIntegrate[expr_String, variable_String, limits_String:"", timeout_:180] :=
    Module[{exprHold, varHold, limHold, key, cached, result, start, elapsed, maxTime},

        exprHold = parseHold[expr];
        varHold = parseHold[variable];

        (* Cache check *)
        key = WolframQFT`Common`cacheKey["wolframIntegrate", expr, variable, limits];
        cached = WolframQFT`Common`cacheGet[key];
        If[cached =!= Missing["Key", key],
            Return[cached]
        ];

        (* Compute *)
        maxTime = Min[timeout, 300];
        start = AbsoluteTime[];
        result = Check[
            TimeConstrained[
                If[limits != "",
                    limHold = parseHold[limits];
                    ReleaseHold[Hold[Integrate][exprHold, limHold]],
                    ReleaseHold[Hold[Integrate][exprHold, varHold]]
                ],
                maxTime,
                "[TIMEOUT] wolframIntegrate exceeded " <> ToString[maxTime] <> "s."],
            "[ERROR] wolframIntegrate failed.",
            {General::all}
        ];
        elapsed = Round[AbsoluteTime[] - start, 0.01];

        result = ToString[result, OutputForm];
        result = result <> "\n[wolframIntegrate elapsed: " <> ToString[elapsed] <> "s]";

        If[!StringContainsQ[result, "[TIMEOUT]"] && !StringContainsQ[result, "[ERROR]"],
            WolframQFT`Common`cachePut[key, result]
        ];

        result
    ];

(* ═══════════════════════════════════════════════════════════════ *)
(* wolfram_differentiate *)
(* ═══════════════════════════════════════════════════════════════ *)
wolframDifferentiate[expr_String, variable_String, order_:1, timeout_:60] :=
    Module[{exprHold, varHold, key, cached, result, start, elapsed, maxTime},

        exprHold = parseHold[expr];
        varHold = parseHold[variable];

        key = WolframQFT`Common`cacheKey["wolframDifferentiate", expr, variable, ToString[order]];
        cached = WolframQFT`Common`cacheGet[key];
        If[cached =!= Missing["Key", key],
            Return[cached]
        ];

        maxTime = Min[timeout, 300];
        start = AbsoluteTime[];
        result = Check[
            TimeConstrained[
                If[order == 1,
                    ReleaseHold[Hold[D][exprHold, varHold]],
                    ReleaseHold[Hold[D][exprHold, {varHold, order}]]
                ],
                maxTime,
                "[TIMEOUT] wolframDifferentiate exceeded " <> ToString[maxTime] <> "s."],
            "[ERROR] wolframDifferentiate failed.",
            {General::all}
        ];
        elapsed = Round[AbsoluteTime[] - start, 0.01];

        result = ToString[result, OutputForm];
        result = result <> "\n[wolframDifferentiate elapsed: " <> ToString[elapsed] <> "s]";

        If[!StringContainsQ[result, "[TIMEOUT]"] && !StringContainsQ[result, "[ERROR]"],
            WolframQFT`Common`cachePut[key, result]
        ];

        result
    ];

(* ═══════════════════════════════════════════════════════════════ *)
(* wolfram_simplify *)
(* ═══════════════════════════════════════════════════════════════ *)
wolframSimplify[expr_String, method_:"simplify", timeout_:120] :=
    Module[{exprHold, key, cached, result, start, elapsed, maxTime},

        exprHold = parseHold[expr];

        key = WolframQFT`Common`cacheKey["wolframSimplify", expr, method];
        cached = WolframQFT`Common`cacheGet[key];
        If[cached =!= Missing["Key", key],
            Return[cached]
        ];

        maxTime = Min[If[method === "auto", Max[timeout, 180], timeout], 300];
        start = AbsoluteTime[];

        If[method === "auto",
            (* Auto mode: iterate Simplify ↔ FullSimplify, track best by LeafCount *)
            result = Check[
                TimeConstrained[
                    Module[{current, best, bestLC, i, simplified},
                        current = Simplify[ReleaseHold[exprHold]];
                        best = current;
                        bestLC = LeafCount[current];
                        For[i = 1, i <= 3, i++,
                            simplified = Simplify[current];
                            If[LeafCount[simplified] < bestLC,
                                best = simplified; bestLC = LeafCount[simplified]; current = simplified
                            ];
                            simplified = FullSimplify[current];
                            If[LeafCount[simplified] < bestLC,
                                best = simplified; bestLC = LeafCount[simplified]; current = simplified
                            ];
                            If[LeafCount[current] >= bestLC && i > 1, Break[]]
                        ];
                        best
                    ],
                    maxTime,
                    "[TIMEOUT] wolframSimplify auto exceeded " <> ToString[maxTime] <> "s."],
                "[ERROR] wolframSimplify auto failed.",
                {General::all}
            ]
            ,
            (* Named method — release Hold before applying *)
            result = Check[
                TimeConstrained[
                    ReleaseHold[Switch[method,
                        "simplify",      Hold[Simplify][exprHold],
                        "fullsimplify",  Hold[FullSimplify][exprHold],
                        "expand",        Hold[Expand][exprHold],
                        "factor",        Hold[Factor][exprHold],
                        "together",      Hold[Together][exprHold],
                        "apart",         Hold[Apart][exprHold],
                        "trigreduce",    Hold[TrigReduce][exprHold],
                        "trigexpand",    Hold[TrigExpand][exprHold],
                        "powerexpand",   Hold[PowerExpand][exprHold],
                        "complexexpand", Hold[ComplexExpand][exprHold],
                        "refine",        Hold[Refine][exprHold],
                        _,               "Unknown method: " <> method
                    ]],
                    maxTime,
                    "[TIMEOUT] wolframSimplify exceeded " <> ToString[maxTime] <> "s."],
                "[ERROR] wolframSimplify failed.",
                {General::all}
            ]
        ];

        elapsed = Round[AbsoluteTime[] - start, 0.01];
        result = ToString[result, OutputForm];
        result = result <> "\n[wolframSimplify elapsed: " <> ToString[elapsed] <> "s]";

        If[!StringContainsQ[result, "[TIMEOUT]"] && !StringContainsQ[result, "[ERROR]"] &&
           !StringContainsQ[result, "Unknown method"],
            WolframQFT`Common`cachePut[key, result]
        ];

        result
    ];

(* ═══════════════════════════════════════════════════════════════ *)
(* wolfram_matrix *)
(* ═══════════════════════════════════════════════════════════════ *)
wolframMatrix[matrix_String, operation_String, vector_String:"", timeout_:120] :=
    Module[{mHold, vHold, fn, key, cached, result, start, elapsed, maxTime},

        mHold = parseHold[matrix];

        fn = Switch[operation,
            "det",          Hold[Det][mHold],
            "inv",          Hold[Inverse][mHold],
            "eigenvalues",  Hold[Eigenvalues][mHold],
            "eigenvectors", Hold[Eigenvectors][mHold],
            "transpose",    Hold[Transpose][mHold],
            "rank",         Hold[MatrixRank][mHold],
            "nullspace",    Hold[NullSpace][mHold],
            "charpoly",     Hold[CharacteristicPolynomial][mHold, x],
            "jordan",       Hold[JordanDecomposition][mHold],
            "svd",          Hold[SingularValueDecomposition][mHold],
            "solve",
                If[vector == "",
                    Return["Vector required for 'solve' operation."]
                ];
                vHold = parseHold[vector];
                Hold[LinearSolve][mHold, vHold],
            _,
                Return["Unknown operation: " <> operation <>
                    ". Use: det, inv, eigenvalues, eigenvectors, transpose, rank, nullspace, charpoly, jordan, svd, solve."]
        ];

        key = WolframQFT`Common`cacheKey["wolframMatrix", matrix, operation, vector];
        cached = WolframQFT`Common`cacheGet[key];
        If[cached =!= Missing["Key", key],
            Return[cached]
        ];

        maxTime = Min[timeout, 300];
        start = AbsoluteTime[];
        result = Check[
            TimeConstrained[ReleaseHold[fn], maxTime,
                "[TIMEOUT] wolframMatrix exceeded " <> ToString[maxTime] <> "s."],
            "[ERROR] wolframMatrix failed.",
            {General::all}
        ];
        elapsed = Round[AbsoluteTime[] - start, 0.01];

        result = ToString[result, OutputForm];
        result = result <> "\n[wolframMatrix elapsed: " <> ToString[elapsed] <> "s]";

        If[!StringContainsQ[result, "[TIMEOUT]"] && !StringContainsQ[result, "[ERROR]"],
            WolframQFT`Common`cachePut[key, result]
        ];

        result
    ];

(* ═══════════════════════════════════════════════════════════════ *)
(* wolfram_numeric *)
(* ═══════════════════════════════════════════════════════════════ *)
wolframNumeric[operation_String, expr_String, range_String:"", opts_String:"{}", timeout_:180] :=
    Module[{exprHold, rangeHold, fn, key, cached, result, start, elapsed, maxTime},

        exprHold = parseHold[expr];

        fn = Switch[operation,
            "nintegrate",
                If[range == "", Return["Range required. Example: {x, 0, Infinity}"]];
                rangeHold = parseHold[range];
                Hold[NIntegrate][exprHold, rangeHold],
            "nsum",
                If[range == "", Return["Range required. Example: {n, 1, Infinity}"]];
                rangeHold = parseHold[range];
                Hold[NSum][exprHold, rangeHold],
            "findroot",
                If[range == "", Return["Initial guess required. Example: {x, 2}"]];
                rangeHold = parseHold[range];
                Hold[FindRoot][exprHold, rangeHold],
            "nminimize",
                If[range == "", Return["Variables required. Example: {x, y}"]];
                rangeHold = parseHold[range];
                Hold[NMinimize][exprHold, rangeHold],
            "nmaximize",
                If[range == "", Return["Variables required. Example: {x, y}"]];
                rangeHold = parseHold[range];
                Hold[NMaximize][exprHold, rangeHold],
            "nlimit",
                If[range == "", Return["Limit point required. Example: x -> 0"]];
                Quiet[Get["NumericalCalculus`"]];
                rangeHold = parseHold[range];
                Hold[NumericalCalculus`NLimit][exprHold, rangeHold],
            _,
                Return["Unknown operation: " <> operation <>
                    ". Use: nintegrate, nsum, findroot, nminimize, nmaximize, nlimit."]
        ];

        key = WolframQFT`Common`cacheKey["wolframNumeric", operation, expr, range];
        cached = WolframQFT`Common`cacheGet[key];
        If[cached =!= Missing["Key", key],
            Return[cached]
        ];

        maxTime = Min[timeout, 300];
        start = AbsoluteTime[];
        result = Check[
            TimeConstrained[ReleaseHold[fn], maxTime,
                "[TIMEOUT] wolframNumeric exceeded " <> ToString[maxTime] <> "s."],
            "[ERROR] wolframNumeric failed.",
            {General::all}
        ];
        elapsed = Round[AbsoluteTime[] - start, 0.01];

        result = ToString[result, OutputForm];
        result = result <> "\n[wolframNumeric elapsed: " <> ToString[elapsed] <> "s]";

        If[!StringContainsQ[result, "[TIMEOUT]"] && !StringContainsQ[result, "[ERROR]"],
            WolframQFT`Common`cachePut[key, result]
        ];

        result
    ];

(* ═══════════════════════════════════════════════════════════════ *)
(* wolfram_assume *)
(* ═══════════════════════════════════════════════════════════════ *)
wolframAssume[action_String, arg_String:""] := Module[{exprHold},
    Switch[action,
        "set",
            If[arg == "", Return["Argument required. Example: wolframAssume[\"set\", \"x > 0\"]"]];
            exprHold = parseHold[arg];
            $Assumptions = ReleaseHold[exprHold];
            WolframQFT`Common`$clearCache[];
            "Assumptions set to: " <> ToString[$Assumptions, OutputForm],
        "add",
            If[arg == "", Return["Argument required. Example: wolframAssume[\"add\", \"Element[n, Integers]\"]"]];
            exprHold = parseHold[arg];
            $Assumptions = $Assumptions && ReleaseHold[exprHold];
            WolframQFT`Common`$clearCache[];
            "Assumptions updated to: " <> ToString[$Assumptions, OutputForm],
        "clear",
            $Assumptions = True;
            WolframQFT`Common`$clearCache[];
            "Assumptions cleared.",
        "view",
            "Current assumptions: " <> ToString[$Assumptions, OutputForm],
        _,
            "Unknown action: " <> action <> ". Use: set, add, clear, view."
    ]
];

End[];
EndPackage[];
