(* WolframQFT Plot Tools — v2.0 simplified *)
BeginPackage["WolframQFT`PlotTools`"];

wolframPlot::usage = "wolframPlot[f, range, w, h] — 2D function plot → base64 PNG.";
wolframPlot3D::usage = "wolframPlot3D[f, range, w, h] — 3D surface plot → base64 PNG.";
wolframParametricPlot::usage = "wolframParametricPlot[x, y, range, w, h] — parametric plot → base64 PNG.";

Begin["`Private`"];

(* ── 2D Plot ────────────────────────────────────────────────── *)
wolframPlot[f_String, r_String, w_:600, h_:400] := Module[{fExpr, rExpr, plot},
    fExpr = ReleaseHold[ToExpression[f, InputForm, Hold]];
    rExpr = ReleaseHold[ToExpression[r, InputForm, Hold]];
    plot = Quiet[Check[
        Plot[fExpr, rExpr, ImageSize -> {Min[w, 1200], Min[h, 1200]}, PlotRange -> All],
        $Failed
    ]];
    If[Head[plot] === Graphics,
        WolframQFT`Common`exportImageBase64[plot],
        "[ERROR] wolframPlot failed. Check function and range syntax."
    ]
];

(* ── 3D Plot — v2.1 robust range parsing ───────────────────────── *)
wolframPlot3D[f_String, r_String, w_:600, h_:500] := Module[
    {fExpr, rExpr, rList, plot, ranges},
    fExpr = ReleaseHold[ToExpression[f, InputForm, Hold]];

    (* Robust range parsing: try parsing as list-of-ranges first,
       fall back to comma-separated ranges *)
    rExpr = Quiet[Check[
        ToExpression[r, InputForm, Hold],
        $Failed
    ]];
    If[rExpr === $Failed,
        Return["[ERROR] wolframPlot3D: could not parse range: " <> r]
    ];
    rExpr = ReleaseHold[rExpr];

    (* Normalize to list of ranges *)
    If[Head[rExpr] === List && MatchQ[rExpr, {{_, _, _}..}],
        rList = rExpr,
        If[Head[rExpr] === List && MatchQ[rExpr, {_, _, _}],
            rList = {rExpr},
            Return["[ERROR] wolframPlot3D: range must be {var,min,max} or {{var1,min1,max1}, {var2,min2,max2}}. Got: " <> ToString[rExpr, InputForm]]
        ]
    ];

    plot = Quiet[Check[
        Plot3D[fExpr, Evaluate[Sequence @@ rList],
            ImageSize -> {Min[w, 1200], Min[h, 1200]}, PlotRange -> All],
        $Failed
    ]];
    If[Head[plot] === Graphics3D,
        WolframQFT`Common`exportImageBase64[plot],
        "[ERROR] wolframPlot3D failed. Check function and ranges."
    ]
];

(* ── Parametric Plot ────────────────────────────────────────── *)
wolframParametricPlot[xe_String, ye_String, pr_String, w_:600, h_:400] := Module[
    {xExpr, yExpr, prExpr, plot},
    xExpr = ReleaseHold[ToExpression[xe, InputForm, Hold]];
    yExpr = ReleaseHold[ToExpression[ye, InputForm, Hold]];
    prExpr = ReleaseHold[ToExpression[pr, InputForm, Hold]];

    plot = Quiet[Check[
        ParametricPlot[{xExpr, yExpr}, prExpr,
            ImageSize -> {Min[w, 1200], Min[h, 1200]}, PlotRange -> All],
        $Failed
    ]];
    If[Head[plot] === Graphics,
        WolframQFT`Common`exportImageBase64[plot],
        "[ERROR] wolframParametricPlot failed. Check expressions and range."
    ]
];

End[];
EndPackage[];
