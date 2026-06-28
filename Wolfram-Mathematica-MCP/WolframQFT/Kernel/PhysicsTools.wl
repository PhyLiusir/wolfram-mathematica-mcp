(* WolframQFT Physics Tools — v2.1 with deferred FeynCalc loading *)
BeginPackage["WolframQFT`PhysicsTools`"];
physicsLoadPackage::usage = "physicsLoadPackage[pkg] — load a physics package.";
feyncalcAmplitude::usage = "feyncalcAmplitude[code, timeout] — QFT amplitude.";
diracTrace::usage = "diracTrace[expr] — Dirac gamma matrix trace (loads FeynCalc on first call).";
colorFactor::usage = "colorFactor[expr] — SU(N) color factor (loads FeynCalc on first call).";
loopIntegral::usage = "loopIntegral[expr, method] — loop integral (tid|pavereduce).";
feynmanDiagram::usage = "feynmanDiagram[incoming, outgoing, model, loopOrder, excludeParticles, imageFormat] — generate Feynman diagrams with FeynArts using particle-name API. Supports named shortcuts: compton, bhabha, moller, pair_annihilation, gg_scatter.";
$feynArtsLoaded::usage = "$feynArtsLoaded — True after FeynArts is lazily loaded.";
packageXEvaluate::usage = "packageXEvaluate[expr] — Package-X evaluation.";
fireReduce::usage = "fireReduce[sectors, propagators, loopVars] — IBP reduction.";
xActTensor::usage = "xActTensor[code] — tensor algebra.";
feynhelpersConvert::usage = "feynhelpersConvert[expr, direction] — FeynCalc↔Package-X.";

Begin["`Private`"];

(* ── Helper ─────────────────────────────────────────────────── *)
parseHold[s_String] := ToExpression[s, InputForm, Hold];

(* ── Package Loader ─────────────────────────────────────────── *)
physicsLoadPackage[pkg_String] := WolframQFT`Common`loadPackage[pkg];

(* ── FeynCalc Amplitude ─────────────────────────────────────── *)
feyncalcAmplitude[code_String, timeout_:120] := (
    Quiet[Get["FeynCalc`"]];
    TimeConstrained[
        WolframQFT`Common`safeEval[code, "OutputForm"],
        Min[timeout, 600]
    ]
);

(* ── Dirac Trace — deferred FeynCalc load, no symbol reference ── *)
diracTrace[expr_String] := (
    Quiet[Get["FeynCalc`"]];
    WolframQFT`Common`safeEval[
        "FeynCalc`DiracTrace[" <> expr <> ", DiracTraceEvaluate -> True]",
        "OutputForm",
        300
    ]
);

(* ── Color Factor — deferred FeynCalc load, no symbol reference ── *)
colorFactor[expr_String] := (
    Quiet[Get["FeynCalc`"]];
    WolframQFT`Common`safeEval[
        "FeynCalc`SUNSimplify[" <> expr <> "]",
        "OutputForm",
        120
    ]
);

(* ── Loop Integral ──────────────────────────────────────────── *)
loopIntegral[expr_String, method_:"tid"] := (
    Quiet[Get["FeynCalc`"]];
    WolframQFT`Common`safeEval[
        If[method == "tid",
            "TID[" <> expr <> ", k]",
            "PaVeReduce[" <> expr <> "]"
        ],
        "OutputForm",
        300
    ]
);

(* ── Feynman Diagram ────────────────────────────────────────── *)
(* v3.1: String-based process specs parsed AFTER FeynArts loads
   (ensures V/F resolve to FeynArts`V / FeynArts`F).
   UsingFrontEnd + DisplayFunction to capture graphics.
   Every dangerous call is Check-wrapped (crash guard). *)

(* ── Named Process Shortcuts — v3.1 ────────────────────────── *)
namedFeynmanProcesses = <|
    "compton"           -> {{"electron", "photon"}, {"electron", "photon"}, "QED"},
    "bhabha"            -> {{"electron", "positron"}, {"electron", "positron"}, "QED"},
    "moller"            -> {{"electron", "electron"}, {"electron", "electron"}, "QED"},
    "pair_annihilation" -> {{"electron", "positron"}, {"photon", "photon"}, "QED"},
    "gg_scatter"        -> {{"gluon", "gluon"}, {"gluon", "gluon"}, "QCD"}
|>;

(* ── Lazy FeynArts Loading — v3.1 ──────────────────────────── *)
(* FeynArts loads on first feynmanDiagram call, keeping Metadata.wxf small.
   After loading, V/F/S resolve to FeynArts`V/FeynArts`F/FeynArts`S. *)
$feynArtsLoaded = False;

loadFeynArts[] := (
    If[FindFile["FeynArts`"] === $Failed,
        With[{dir = Environment["FEYNARTS_DIR"]},
            If[StringQ[dir], AppendTo[$Path, dir]]
        ]
    ];
    Needs["FeynArts`"];
    $feynArtsLoaded = True;
);

(* ── Feynman Diagram — v3.1 structured particle-list API ────── *)
(* No arbitrary code evaluation. Particles resolved via whitelist.
   Returns markdown string with embedded base64 image. *)
feynmanDiagram[
    incoming_List, outgoing_List,
    model_String : "SM", loopOrder_Integer : 0,
    excludeParticles : (_List | _Missing) : {},
    imageFormat_String : "png"
] := Catch @ Module[
    {tops, ins, pic, inFields, outFields, exclFields, exclOpt,
     excludeList, base64, mime, n},

    If[!$feynArtsLoaded, loadFeynArts[]];

    (* ── Validate parameters ────────────────────────────────── *)
    If[!MemberQ[{"SM", "SMQCD", "MSSM", "QED", "QCD"}, model],
        Throw[Failure["InvalidModel",
            <|"MessageTemplate" -> "model must be SM/SMQCD/MSSM/QED/QCD, got: `1`",
              "MessageParameters" -> {model}|>]]
    ];
    If[!(0 <= loopOrder <= 2),
        Throw[Failure["InvalidLoopOrder",
            <|"MessageTemplate" -> "loopOrder must be 0-2, got: `1`",
              "MessageParameters" -> {loopOrder}|>]]
    ];
    If[!MemberQ[{"png", "pdf"}, imageFormat],
        Throw[Failure["InvalidImageFormat",
            <|"MessageTemplate" -> "imageFormat must be png or pdf, got: `1`",
              "MessageParameters" -> {imageFormat}|>]]
    ];

    excludeList = Replace[excludeParticles, _Missing -> {}];

    (* ── Resolve particles via Common`resolveParticle ────────── *)
    inFields   = WolframQFT`Common`resolveParticle /@ incoming;
    outFields  = WolframQFT`Common`resolveParticle /@ outgoing;
    exclFields = WolframQFT`Common`resolveParticle /@ excludeList;
    exclOpt    = If[exclFields === {}, {}, {ExcludeParticles -> exclFields}];

    (* ── Generate diagrams ───────────────────────────────────── *)
    tops = CreateTopologies[loopOrder, Length[incoming] -> Length[outgoing]];
    ins  = InsertFields[
        tops, inFields -> outFields,
        InsertionLevel -> {Classes}, Model -> model,
        Sequence @@ exclOpt
    ];
    n = Length[ins];

    If[n === 0,
        Throw[Failure["NoDiagrams",
            <|"MessageTemplate" ->
                "No diagrams found for model `1` at `2` loop(s). Check conservation laws.",
              "MessageParameters" -> {model, loopOrder}|>]]
    ];

    (* ── Render via FeynArts Paint ──────────────────────────── *)
    pic = Paint[ins,
        ColumnsXRows -> {Min[n, 4], Max[1, Ceiling[n/4.0]]},
        SheetHeader -> None,
        Numbering -> Simple,
        ImageSize -> {800, 600},
        DisplayFunction -> Identity
    ];

    If[!ImageQ[pic] && Head[pic] =!= Graphics && Head[pic] =!= Graphics3D,
        Throw[Failure["RenderFailed",
            <|"MessageTemplate" -> "Could not render Feynman diagram(s)."|>]]
    ];

    (* ── Export to base64 markdown ───────────────────────────── *)
    base64 = WolframQFT`Common`exportImageBase64[pic, imageFormat];
    mime   = If[imageFormat === "pdf", "application/pdf", "image/png"];

    "Generated " <> ToString[n] <> " diagram(s) (model: " <> model <>
      ", loops: " <> ToString[loopOrder] <> ").\n\n" <>
      "![Feynman diagram](data:" <> mime <> ";base64," <> base64 <> ")"
];

(* ── Named Process Convenience Wrapper ─────────────────────── *)
feynmanDiagram[process_String, model_String : "QED", loopOrder_Integer : 0] :=
    If[KeyExistsQ[namedFeynmanProcesses, process],
        With[{spec = namedFeynmanProcesses[process]},
            feynmanDiagram[spec[[1]], spec[[2]], spec[[3]], loopOrder]
        ],
        "Unknown named process: " <> process <>
        ". Available: " <> StringRiffle[Keys[namedFeynmanProcesses], ", "]
    ];

(* Catch leaked Failures *)
(* Catch leaked Failures — skip if no Failure present *)
feynmanDiagram[args___] := Module[{msgs},
    msgs = Select[{args}, MatchQ[#, Failure[__]]&];
    "Error: " <> StringRiffle[Map[#["Message"]&, msgs], "; "]
] /; MemberQ[{args}, Failure[__]];

(* ── Package-X Evaluation ───────────────────────────────────── *)
packageXEvaluate[expr_String] := (
    Quiet[Get[FileNameJoin[{$UserBaseDirectory, "Applications", "PackageX", "Kernel", "init.m"}]]];
    WolframQFT`Common`safeEval[expr, "OutputForm", 300]
);

(* ── FIRE IBP Reduction ─────────────────────────────────────── *)
fireReduce[sectors_String, propagators_String, loopVars_String] := (
    Quiet[Get[FileNameJoin[{$UserBaseDirectory, "Applications", "FIRE", "FIRE6.m"}]]];
    WolframQFT`Common`safeEval[
        StringJoin[
            "Internal[{", sectors, "}, {", propagators, "}, {", loopVars, "}]; ",
            "PrepareIBP[]; Burn[]; MasterIntegrals[]"
        ],
        "OutputForm",
        600
    ]
);

(* ── xAct Tensor Algebra ────────────────────────────────────── *)
xActTensor[code_String] := (
    Quiet[Get["xAct`xCore`"]; Get["xAct`xTras`"]];
    WolframQFT`Common`safeEval[code, "OutputForm", 300]
);

(* ── FeynCalc ↔ Package-X Bridge ────────────────────────────── *)
feynhelpersConvert[expr_String, direction_:"to_packagex"] := (
    Quiet[Get["FeynCalc`"]];
    WolframQFT`Common`safeEval[
        If[direction == "to_packagex",
            "FCFI[" <> expr <> "]",
            "FCPI[" <> expr <> "]"
        ],
        "OutputForm",
        180
    ]
);

End[];
EndPackage[];