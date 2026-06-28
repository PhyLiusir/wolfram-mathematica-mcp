(* WolframQFT Common Utilities — v1.1 with security, cache, structured output *)
BeginPackage["WolframQFT`Common`"];

$SecurityLevel::usage = "Security level: \"permissive\" | \"moderate\" (default) | \"strict\". Set via WOLFRAMQFT_SECURITY_LEVEL env var.";
$ResultCache::usage = "Result cache (Association). Max 1000 entries, LRU eviction.";
safeEval::usage = "safeEval[code, form, timeout] — secure evaluation with security check, cache, timeout.";
checkSecurity::usage = "checkSecurity[code] — returns True if safe, $Failed with message if blocked.";
formatResult::usage = "formatResult[result, opts] — wraps output in structured JSON.";
exportImageBase64::usage = "exportImageBase64[g] rasterizes graphics to base64 PNG.";
loadPackage::usage = "loadPackage[name] loads a physics package.";
$clearCache::usage = "$clearCache[] clears the result cache.";
cacheStats::usage = "cacheStats[] returns cache hit/miss stats.";
cacheGet::usage = "cacheGet[key] retrieves from cache.";
cachePut::usage = "cachePut[key, value] stores in cache.";
cacheKey::usage = "cacheKey[args...] generates a cache key hash.";
$dangerousPermissive::usage = "$dangerousPermissive — symbols blocked in permissive mode.";
$dangerousModerate::usage = "$dangerousModerate — symbols blocked in moderate mode.";
$dangerousStrict::usage = "$dangerousStrict — symbols blocked in strict mode.";

Begin["`Private`"];

(* ── Security Level ─────────────────────────────────────────── *)
$SecurityLevel = Lookup[
    Association[Quiet[GetEnvironment["WOLFRAMQFT_SECURITY_LEVEL"]]],
    "WOLFRAMQFT_SECURITY_LEVEL",
    "moderate"
];
If[!MemberQ[{"permissive", "moderate", "strict"}, $SecurityLevel],
    $SecurityLevel = "moderate"
];

(* ── Dangerous Symbols Blocklist ────────────────────────────── *)
$dangerousPermissive = {
    "DeleteFile", "DeleteDirectory", "Remove", "Uninstall",
    "Run", "RunProcess", "RunThrough", "Quit", "Exit"
};

$dangerousModerate = Join[$dangerousPermissive, {
    (* File I/O *)
    "OpenRead", "OpenWrite", "OpenAppend", "Write", "WriteString",
    "Put", "PutAppend", "Get", "Needs", "Import", "Export",
    "Save", "DumpSave", "DumpGet", "BinaryRead", "BinaryWrite",
    "CopyFile", "RenameFile", "CreateDirectory", "CopyDirectory",
    "RenameDirectory", "FileNames", "ReadList", "ReadString",
    (* Network *)
    "URLFetch", "URLRead", "URLSave", "URLExecute", "URLSubmit",
    "SocketConnect", "SocketListen", "SocketOpen",
    "CloudConnect", "CloudDeploy", "CloudEvaluate", "CloudExport",
    "SendMail", "HTTPRequest", "HTTPResponse",
    (* External processes *)
    "SystemOpen", "Install", "Spawn", "ShellExecute",
    "LibraryFunctionLoad", "ExternalEvaluate", "ExternalFunction",
    (* Kernel control *)
    "Abort", "Interrupt", "Pause",
    (* Reflection (dangerous in code strings) *)
    "ToExpression", "Symbol", "SymbolName", "ClearAll",
    "Unprotect", "Protect",
    (* System info export *)
    "Environment", "$MachineName", "$ProcessID",
    (* Notebook/FrontEnd *)
    "NotebookOpen", "NotebookSave", "NotebookEvaluate",
    "FrontEndExecute", "FrontEndTokenExecute",
    (* Template injection *)
    "TemplateApply", "TemplateEvaluate",
    (* Cloud / submission *)
    "SessionSubmit", "LocalSubmit", "RemoteRun"
}];

$dangerousStrict = Join[$dangerousModerate, {
    "Table", "Do", "For", "While", "NestWhile", "FixedPoint",
    "Compile", "Function", "Module", "Block", "With",
    "Set", "SetDelayed", "TagSet", "UpSet",
    "Map", "Apply", "Scan", "Fold",
    "Print", "Message", "Echo",
    "StringReplace", "StringJoin",
    "Compress", "Uncompress",
    "Encode", "Decode"
}];

(* ── Security Check Function ────────────────────────────────── *)
checkSecurity[code_String] := Module[{stripped, tokens, blocked, level},
    level = $SecurityLevel;
    If[level === "off", Return[True]];

    (* Strip string literals to avoid false positives *)
    stripped = StringReplace[code, "\"" ~~ Shortest[___] ~~ "\"" :> "\"\""];

    (* Get list of blocked symbols for current level *)
    blocked = Switch[level,
        "permissive", $dangerousPermissive,
        "moderate",   $dangerousModerate,
        "strict",     $dangerousStrict,
        _,            $dangerousModerate
    ];

    (* Check each blocked symbol *)
    tokens = StringCases[stripped, blocked, IgnoreCase -> False];
    If[tokens =!= {},
        Return["[SECURITY BLOCKED: " <> level <> "] Forbidden symbols: " <>
            StringRiffle[DeleteDuplicates[tokens], ", "]]
    ];

    True
];

(* ── Result Cache ───────────────────────────────────────────── *)
If[!AssociationQ[$ResultCache], $ResultCache = <||>];
$MaxCacheSize = 1000;
$CacheHits = 0;
$CacheMisses = 0;

cacheKey[args__] := Hash[{args}, "MD5"];

cachePut[key_, result_] := Module[{},
    If[Length[$ResultCache] >= $MaxCacheSize,
        $ResultCache = KeyDrop[$ResultCache, First[Keys[$ResultCache]]]
    ];
    $ResultCache[key] = result
];

cacheGet[key_] := Module[{val},
    val = Lookup[$ResultCache, key, Missing["Key", key]];
    If[val =!= Missing["Key", key], $CacheHits++];
    val
];

$clearCache[] := Module[{n},
    n = Length[$ResultCache];
    $ResultCache = <||>;
    $CacheHits = 0;
    $CacheMisses = 0;
    "Cache cleared (" <> ToString[n] <> " entries removed)."
];

cacheStats[] := Module[{},
    "Cache: " <> ToString[Length[$ResultCache]] <> " entries, " <>
    ToString[$CacheHits] <> " hits. " <>
    "Misses tracked by safeEval: " <> ToString[$CacheMisses] <> "."
];

(* ── Safe Evaluation Engine — v1.3 Missing-resilient ──────────── *)
(* Primary definitions: match specific types *)
safeEval[code_String] := safeEval[code, "OutputForm", 60];
safeEval[code_String, form_String] := safeEval[code, form, 60];

(* Fallback: sanitize Missing["NoInput"] from MCP framework *)
safeEval[code_, form_, timeout_] := safeEval[
    If[StringQ[code], code, ToString[code, InputForm]],
    If[StringQ[form], form, "OutputForm"],
    If[IntegerQ[timeout], timeout, 60]
];

(* Core implementation: String + String + Integer *)
safeEval[code_String, form_String, timeout_Integer] := Module[
    {secCheck, key, cached, held, result, start, elapsed, maxTime, fmt},

    (* 1. Security check *)
    secCheck = checkSecurity[code];
    If[secCheck =!= True, Return[secCheck]];

    (* 2. Cache check *)
    key = cacheKey[code, form];
    cached = cacheGet[key];
    If[cached =!= Missing["Key", key],
        $CacheHits++;
        Return[cached];
    ];
    $CacheMisses++;

    (* 3. Evaluate with timeout — v1.2 crash guard *)
    maxTime = Min[timeout, 300];
    start = AbsoluteTime[];
    held = Check[
        ToExpression[code, InputForm, Hold],
        Return["[ERROR] Syntax error — code parsing failed."],
        {General::all}
    ];
    If[held === $Failed, Return["[ERROR] Syntax error in code."]];
    result = Check[
        TimeConstrained[
            ToString[ReleaseHold[held], ToExpression[form]],
            maxTime,
            "[TIMEOUT] Exceeded " <> ToString[maxTime] <> "s limit."
        ],
        "[ERROR] Computation failed.",
        {General::all}
    ];
    elapsed = Round[AbsoluteTime[] - start, 0.01];

    (* 4. Format result with elapsed time *)
    If[StringContainsQ[result, "[TIMEOUT]"] || StringContainsQ[result, "[ERROR]"],
        result = result <> " (elapsed: " <> ToString[elapsed] <> "s)"
        ,
        result = result <> "\n[elapsed: " <> ToString[elapsed] <> "s]";
    ];

    (* 5. Cache on success *)
    If[!StringContainsQ[result, "[TIMEOUT]"] && !StringContainsQ[result, "[ERROR]"] &&
       !StringContainsQ[result, "[SECURITY BLOCKED"],
        cachePut[key, result]
    ];

    result
];

(* ── Structured Output Helper ───────────────────────────────── *)
formatResult[result_String, opts___Rule] := Module[{status, warnings, elapsedTime, meta},
    status = Lookup[{opts}, "status", "ok"];
    warnings = Lookup[{opts}, "warnings", {}];
    elapsedTime = Lookup[{opts}, "elapsed", Null];
    meta = <|"status" -> status, "result" -> result|>;
    If[warnings =!= {}, meta["warnings"] = warnings];
    If[elapsedTime =!= Null, meta["elapsed"] = elapsedTime];
    ExportString[meta, "JSON"]
];

(* ── Base64 Image Export ────────────────────────────────────── *)
exportImageBase64[g_] := exportImageBase64[g, "png"];
exportImageBase64[g_, fmt_String:"png"] := Module[{img, bytes},
    img = If[ImageQ[g], g, Rasterize[g, ImageResolution -> 120]];
    bytes = ExportByteArray[img, ToUpperCase[fmt]];
    BaseEncode[bytes]
];

(* ── Shared Particle Table — v1.0 ──────────────────────────── *)
(* Particle names stored as STRINGS to avoid context issues before FeynArts loads.
   resolveParticle does the ToExpression after FeynArts is on $ContextPath. *)
$ParticleTable = <|
    "electron" -> "F[2, {1}]", "e-" -> "F[2, {1}]",
    "positron" -> "-F[2, {1}]", "e+" -> "-F[2, {1}]",
    "muon" -> "F[2, {2}]", "mu-" -> "F[2, {2}]",
    "antimuon" -> "-F[2, {2}]", "mu+" -> "-F[2, {2}]",
    "tau-" -> "F[2, {3}]", "tau+" -> "-F[2, {3}]",
    "electron_neutrino" -> "F[1, {1}]",
    "muon_neutrino" -> "F[1, {2}]",
    "tau_neutrino" -> "F[1, {3}]",
    "photon" -> "V[1]", "gamma" -> "V[1]",
    "Z" -> "V[2]", "Z_boson" -> "V[2]",
    "W-" -> "V[3]", "W+" -> "-V[3]",
    "gluon" -> "V[5]", "g" -> "V[5]",
    "higgs" -> "S[1]", "H" -> "S[1]",
    "u" -> "F[3, {1, 1}]", "d" -> "F[3, {1, 2}]",
    "c" -> "F[3, {2, 1}]", "s" -> "F[3, {2, 2}]",
    "t" -> "F[3, {3, 1}]", "b" -> "F[3, {3, 2}]",
    "u_bar" -> "-F[3, {1, 1}]", "d_bar" -> "-F[3, {1, 2}]",
    "c_bar" -> "-F[3, {2, 1}]", "s_bar" -> "-F[3, {2, 2}]",
    "t_bar" -> "-F[3, {3, 1}]", "b_bar" -> "-F[3, {3, 2}]",
    "up" -> "F[3, {1, 1}]", "down" -> "F[3, {1, 2}]",
    "charm" -> "F[3, {2, 1}]", "strange" -> "F[3, {2, 2}]",
    "top" -> "F[3, {3, 1}]", "bottom" -> "F[3, {3, 2}]",
    "up_bar" -> "-F[3, {1, 1}]", "down_bar" -> "-F[3, {1, 2}]",
    "charm_bar" -> "-F[3, {2, 1}]", "strange_bar" -> "-F[3, {2, 2}]",
    "top_bar" -> "-F[3, {3, 1}]", "bottom_bar" -> "-F[3, {3, 2}]"
|>;

$FieldCodePattern = RegularExpression["^-?[A-Z]\\[\\d+(,\\{\\d+(,\\d+)?\\})?\\]$"];

resolveParticle[name_String] := Module[{raw, defaultVal},
    defaultVal = If[StringMatchQ[name, $FieldCodePattern],
        name,
        Throw[Failure["UnknownParticle",
            <|"MessageTemplate" -> "Unknown particle: `1`. Known: `2`",
              "MessageParameters" -> {name, StringRiffle[Sort@Keys[$ParticleTable], ", "]} |>],
            "WolframQFT`Common`"]
    ];
    raw = Lookup[$ParticleTable, name, defaultVal];
    ToExpression[raw]
];

(* ── Package Loader ─────────────────────────────────────────── *)
loadPackage[name_String] := Module[{cmd, result},
    cmd = Lookup[<|
        "FeynCalc"  -> "Get[\"FeynCalc`\"]",
        "FeynArts"  -> "Get[\"FeynArts`\"]",
        "FeynHelpers" -> "Get[\"FeynHelpers`\"]",
        "PackageX"  -> "Get[FileNameJoin[{$UserBaseDirectory, \"Applications\", \"PackageX\", \"Kernel\", \"init.m\"}]]",
        "FIRE"      -> "Get[FileNameJoin[{$UserBaseDirectory, \"Applications\", \"FIRE\", \"FIRE6.m\"}]]",
        "xAct"      -> "Get[\"xAct`xCore`\"]; Get[\"xAct`xTras`\"]"
    |>, name];

    If[!StringQ[cmd],
        Return["Unknown package: " <> name <> ". Available: FeynCalc, FeynArts, FeynHelpers, PackageX, FIRE, xAct."]
    ];

    result = Check[ToExpression[cmd], $Failed, {Needs::nocont, Get::noopen, General::all}];
    If[result === $Failed,
        "Failed to load: " <> name,
        "Loaded: " <> name
    ]
];

End[];
EndPackage[];

(* NOTE: FeynCalc is no longer preloaded. Use physicsLoadPackage["FeynCalc"] on demand. *)