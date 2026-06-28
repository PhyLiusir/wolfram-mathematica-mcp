(* WolframQFT ServerConfig — v3.0
   Server registration is now handled by setup_once.wl (run once, interactively).
   This file is intentionally empty — server persistence is done by CreateMCPServer at setup time.
   start_mcp.wls calls StartMCPServer["WolframQFT"] to start the pre-registered server. *)

BeginPackage["WolframQFT`ServerConfig`"];
EndPackage[];
