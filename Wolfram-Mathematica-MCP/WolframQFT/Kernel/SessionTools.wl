(* WolframQFT Session Tools — v1.1 with fixed detection + version info *)
BeginPackage["WolframQFT`SessionTools`"];

wolframSessionInfo::usage = "wolframSessionInfo[] — kernel status, loaded packages, versions.";
wolframResetKernel::usage = "wolframResetKernel[confirm] — reset kernel (requires confirm=True).";

Begin["`Private`"];

(* ── Known package versions ─────────────────────────────────── *)
$knownPackageVersions = <|
    "FeynCalc"   -> "10.1.0",
    "FeynArts"   -> "3.12",
    "FeynHelpers"-> "1.2.0",
    "PackageX"   -> "2.1.1",
    "FIRE"       -> "6.5.2",
    "xAct"       -> "0.6.10"
|>;

(* ── Package detection with context matching ────────────────── *)
detectPackage[pkg_String] := Module[{},
    Switch[pkg,
        "FeynCalc",
            MemberQ[Contexts[], "FeynCalc`"] || MemberQ[Contexts[], "FeynCalc`*"],
        "FeynArts",
            MemberQ[Contexts[], "FeynArts`"] || MemberQ[Contexts[], "FeynArts`*"],
        "FeynHelpers",
            MemberQ[Contexts[], "FeynHelpers`"] || MemberQ[Contexts[], "FeynHelpers`*"],
        "PackageX",
            (* Fixed: strictly check for PackageX context, not any X context *)
            MemberQ[Contexts[], "X`"] || MemberQ[Contexts[], "PackageX`"] || MemberQ[Contexts[], "PackageX`*"],
        "FIRE",
            MemberQ[Contexts[], "FIRE6`"] || MemberQ[Contexts[], "FIRE6`*"],
        "xAct",
            MemberQ[Contexts[], "xAct`xCore`"] || MemberQ[Contexts[], "xAct`xCore`*"],
        _,
            False
    ]
];

(* ── Session Info ───────────────────────────────────────────── *)
wolframSessionInfo[] := Module[{pkgNames, loaded, loadedVersions, info},
    pkgNames = {"FeynCalc", "FeynArts", "FeynHelpers", "PackageX", "FIRE", "xAct"};
    loaded = Select[pkgNames, detectPackage];

    loadedVersions = StringRiffle[
        Map[# <> " v" <> Lookup[$knownPackageVersions, #, "?"] &, loaded],
        ", "
    ];

    info = {
        "=== Wolfram Kernel Session ===",
        "Mathematica: " <> ToString[$Version],
        "Security:    " <> ToString[WolframQFT`Common`$SecurityLevel],
        "Loaded:      " <> If[loaded == {},
            "(none)",
            loadedVersions
        ],
        "Available:   FeynCalc (10.0.0), FeynArts (3.12), FeynHelpers (1.2.0), PackageX (2.1.1), FIRE (6.5.2), xAct (0.6.10)",
        "Cache:       " <> WolframQFT`Common`cacheStats[],
        "Use physicsLoadPackage[\"name\"] to load a package."
    };
    StringRiffle[info, "\n"]
];

(* ── Kernel Reset ───────────────────────────────────────────── *)
wolframResetKernel[confirm_:False] :=
    If[TrueQ[confirm],
        WolframQFT`Common`$clearCache[];
        Quit[];
        "Kernel terminated. A new session starts on next call.",
        "Reset NOT performed. Set confirm=True to actually reset. WARNING: this terminates the kernel!"
    ];

End[];
EndPackage[];
