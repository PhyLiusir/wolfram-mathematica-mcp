#!/usr/bin/env python3
"""
Standalone PDF Export Tool — No WolframKernel dependency.

Takes pre-computed content (from AgentTools/WL side) and compiles a XeLaTeX PDF.
All computation happens in WL; this script only handles typesetting + compilation.

Usage:
    python wolfram_pdf_standalone.py --title "..." --code "..." --result-tex "..."
              --result-raw "..." [--question "..."] [--notes "..."] [--steps "..."]
              [--images "path1,path2"]
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime

# ── Config ──────────────────────────────────────────────────────────
XELATEX_CANDIDATES = [
    r"D:\For Texlive\texlive\2024\bin\windows\xelatex.exe",
    r"C:\texlive\2024\bin\windows\xelatex.exe",
]
OUTPUT_DIR = r"D:\Awork\Mathematica_Reports"


def find_xelatex():
    for c in XELATEX_CANDIDATES:
        if os.path.isfile(c):
            return c
    fallback = shutil.which("xelatex")
    return fallback or "xelatex"


def tex_escape(text: str) -> str:
    r"""Escape special LaTeX characters in plain text.
    Does NOT escape content already inside math mode ($...$ or \[...\]).
    """
    # Protect math regions first
    math_regions = []
    def save_math(m):
        math_regions.append(m.group(0))
        return f"\x00MATH{len(math_regions)-1}\x00"

    # Save display math \[...\] and $$...$$
    text = re.sub(r'\$\$.*?\$\$', save_math, text, flags=re.DOTALL)
    text = re.sub(r'\\\[.*?\\\]', save_math, text, flags=re.DOTALL)
    # Save inline math $...$
    text = re.sub(r'\$[^$]+?\$', save_math, text)
    # Save \(...\)
    text = re.sub(r'\\\(.*?\\\)', save_math, text)

    # Escape special chars in remaining plain text
    special = {"&": r"\&", "%": r"\%", "#": r"\#",
               "_": r"\_", "{": r"\{", "}": r"\}",
               "~": r"\textasciitilde{}", "^": r"\textasciicircum{}"}
    for ch, repl in special.items():
        text = text.replace(ch, repl)

    # Restore math regions
    for i, region in enumerate(math_regions):
        text = text.replace(f"\x00MATH{i}\x00", region)

    return text


def parse_steps(steps_text: str):
    r"""Parse steps text with [STEP]Title markers into list of {title, content} pairs.

    Format:
        [STEP]Step 1 Title
        Content for step 1 (supports LaTeX math $...$ and \[...\])

        [STEP]Step 2 Title
        Content for step 2
    """
    if not steps_text or not steps_text.strip():
        return []

    # Split by [STEP] markers (at beginning of lines)
    parts = re.split(r'\n(?=\[STEP\])', steps_text.strip())

    steps = []
    for part in parts:
        part = part.strip()
        if not part:
            continue
        # Extract title: everything after [STEP] up to the first newline
        lines = part.split('\n', 1)
        title = lines[0].strip()
        if title.startswith('[STEP]'):
            title = title[6:].strip()
        elif title.startswith('[STEP]'):
            title = title[6:].strip()
        content = lines[1].strip() if len(lines) > 1 else ''
        if title:
            steps.append({'title': title, 'content': content})

    return steps


# ── Width weights for LaTeX math tokens ──────────────────────────
# Tuned for 11pt article, A4, 2.5 cm margins → textwidth ≈ 418 pt
# A "weight unit" ≈ 2.5 pt of rendered width, so max_width ≈ 165

_MATH_WIDTH_MAP = {
    # Wide operators / structures
    '\\sum': 6, '\\int': 5, '\\prod': 5, '\\frac': 5, '\\displaystyle': 0,
    '\\Bigl': 3, '\\Bigr': 3, '\\bigl': 2, '\\bigr': 2, '\\Big': 2, '\\big': 2,
    '\\left': 2, '\\right': 2, '\\sinh': 3, '\\cosh': 3, '\\sin': 2, '\\cos': 2,
    '\\tan': 2, '\\partial': 2, '\\infty': 2, '\\quad': 4, '\\qquad': 8,
    # Punctuation / spacing
    '\\,': 0.3, '\\;': 0.5, '\\ ': 0.3,
    # Symbols
    '\\pi': 1, '\\times': 1.5, '\\cdot': 0.8, '\\mathrm': 0, '\\textbf': 0,
    '\\alpha': 1, '\\beta': 1, '\\gamma': 1, '\\delta': 1, '\\epsilon': 1,
    '\\theta': 1, '\\lambda': 1, '\\mu': 1, '\\sigma': 1, '\\omega': 1,
    '\\Gamma': 1.2, '\\Delta': 1.2, '\\Sigma': 1.2, '\\Omega': 1.2,
    '\\Phi': 1.2, '\\Psi': 1.2, '\\Theta': 1.2, '\\Lambda': 1.2,
}

# Characters that are good places to break a formula line
_BREAK_AFTER = {'=', '+', '-', ','}


def _math_token_width(token: str) -> float:
    """Return the approximate rendered width (in weight units) of a LaTeX token."""
    if token.startswith('\\'):
        return _MATH_WIDTH_MAP.get(token, 1.8)  # unknown commands ~1.8
    if token in '()[]{}':
        return 0.4
    if token in '+-=<>':
        return 0.9
    if token in ',.;:!?':
        return 0.35
    if token in '^_':
        return 0.2
    if token.isdigit():
        return 0.55 * len(token)
    if token.isalpha():
        return 0.65 * len(token)
    return 0.6


def _tokenize_math(formula: str):
    """Yield (token_str, is_breakable, width) for each token in a LaTeX formula.

    is_breakable = True when the token is a potential break point
    (top-level =, +, -, or comma). Only accurate for tokens *not*
    inside nested {} braces; the caller must track brace depth.
    """
    i = 0
    n = len(formula)
    while i < n:
        c = formula[i]

        # Whitespace — preserve as a token (important for readability
        # and for commands like \  (backslash-space))
        if c == ' ':
            yield ' ', False, 0.35
            i += 1
            continue
        if c in '\t\n\r':
            i += 1
            continue

        # LaTeX command: \name
        if c == '\\':
            m = re.match(r'\\([a-zA-Z]+|\[|\]|\(|\)|\{|\}|\$|\,|\;|\ |\\|\_|\^)', formula[i:])
            if m:
                tok = m.group()
                yield tok, False, _math_token_width(tok)
                i += len(tok)
                continue
            # Stray backslash followed by non-alpha — treat as char
            i += 1
            continue

        # Digits
        if c.isdigit():
            j = i
            while j < n and formula[j].isdigit():
                j += 1
            tok = formula[i:j]
            yield tok, False, _math_token_width(tok)
            i = j
            continue

        # Alphabetic
        if c.isalpha():
            j = i
            while j < n and formula[j].isalpha():
                j += 1
            tok = formula[i:j]
            yield tok, False, _math_token_width(tok)
            i = j
            continue

        # Sub/superscript
        if c in '^_':
            yield c, False, 0.2
            i += 1
            continue

        # Braces
        if c in '{}':
            yield c, False, 0.3
            i += 1
            continue

        # Brackets / parens
        if c in '()[]':
            yield c, False, 0.4
            i += 1
            continue

        # Operators — potential break points
        if c in '+-=':
            yield c, True, 0.9
            i += 1
            continue

        # Symbols
        if c == ',':
            yield c, True, 0.35
            i += 1
            continue

        # Fallback
        yield c, False, 0.6
        i += 1


def smart_break_math(formula: str, max_width: float = 160) -> str:
    """Insert \\\\ line breaks into a long LaTeX math formula at natural
    break points (top-level +, =, comma, or after \\Bigr)).

    Lines that already contain \\\\ are processed individually (each
    segment may be broken further if too wide).  The returned string
    is plain LaTeX math (no outer \\[\\] or $$).
    """
    formula = formula.strip()
    if not formula:
        return formula

    # If the formula already contains explicit \\\\ breaks, process
    # each segment independently and rejoin with \\\\
    if '\\\\' in formula and not re.search(r'\\begin\{(?:aligned|gathered|split|multlined|array|cases)\}', formula):
        segments = re.split(r'(?<!\\)\\\\(?!\\)', formula)
        broken = []
        for seg in segments:
            seg = seg.strip()
            if seg:
                broken.append(_break_single_segment(seg, max_width))
        return ' \\\\\n'.join(broken)

    # Single formula — break it
    return _break_single_segment(formula, max_width)


def _break_single_segment(segment: str, max_width: float) -> str:
    """Break a single formula segment (no internal \\\\) into multiple lines."""
    # Tokenize
    tokens = list(_tokenize_math(segment))
    if not tokens:
        return segment

    # Track brace depth to only break at *top-level* operators
    lines = []           # completed lines (strings)
    cur_tokens = []      # tokens accumulated on current line
    cur_width = 0.0
    # Position (index into cur_tokens) of last good break point,
    # and the width at that point
    last_break_idx = -1
    last_break_width = 0.0
    depth = 0

    for tok, breakable, w in tokens:
        # Update brace depth BEFORE deciding whether this is a break point
        if tok == '{':
            depth += 1
        elif tok == '}':
            depth = max(0, depth - 1)

        cur_tokens.append(tok)
        cur_width += w

        # Record break point (only at depth 0 and after the token)
        if depth == 0 and breakable:
            last_break_idx = len(cur_tokens)
            last_break_width = cur_width

        # Also allow breaking after \Bigr) / \bigr) at depth 0
        if depth == 0 and tok in ('\\Bigr', '\\bigr', '\\Biggr', '\\biggr'):
            last_break_idx = len(cur_tokens)
            last_break_width = cur_width

        # Over threshold → split at last break point
        if cur_width > max_width and last_break_idx > 0 and last_break_idx < len(cur_tokens):
            # Move everything up to (and including) the break token to the
            # completed line; keep the rest on the current line
            line_tokens = cur_tokens[:last_break_idx]
            cur_tokens = cur_tokens[last_break_idx:]

            lines.append(''.join(line_tokens).strip())

            # Recalculate current width from remaining tokens
            cur_width = sum(
                _math_token_width(t) if t.startswith('\\') else
                (0.55 * len(t) if t.isdigit() else
                 0.65 * len(t) if t.isalpha() else
                 0.4 if t in '()[]{}' else
                 0.9 if t in '+-=<>' else
                 0.35 if t in ',.;:!?' else
                 0.2 if t in '^_' else 0.6)
                for t in cur_tokens
            )
            last_break_idx = -1
            last_break_width = 0.0

    # Flush remaining tokens
    if cur_tokens:
        lines.append(''.join(cur_tokens).strip())

    if len(lines) <= 1:
        return segment  # no break needed

    return ' \\\\\\\n'.join(lines)


def fix_latex_spacing(text: str) -> str:
    r"""Fix single-backslash LaTeX spacing commands like \[4pt] to \\[4pt].

    In LaTeX, line breaks with spacing are written as \\[4pt] or \\[2cm].
    If a single backslash reaches us (e.g. \[4pt]), LaTeX interprets \[ as
    a math display opener, causing 'Bad math environment delimiter' errors.

    Only fixes when \[digits unit] is NOT already preceded by another \.
    """
    # Match: exactly ONE backslash before [digits unit] where the backslash
    # is NOT preceded by another backslash, and NOT inside math mode
    # Pattern: (?<!\\) — no backslash before; \\ — one backslash;
    #          \[ — literal [; (\d+\.?\d*) — number; (pt|cm|mm|em|ex|in) — unit; \] — literal ]
    import re
    pattern = r'(?<!\\)\\(?=\[\d+\.?\d*(?:pt|cm|mm|em|ex|in)\])'
    fixed = re.sub(pattern, r'\\\\', text)
    return fixed


def build_latex(title, code, result_tex, result_raw, question="", notes="", steps="", analysis="", image_paths=None):
    """Build a complete LaTeX document."""
    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    title_safe = tex_escape(title)

    # Figures
    figures = ""
    if image_paths:
        figures = "\\section{Figures \\& Diagrams}\n"
        for i, img in enumerate(image_paths):
            img = img.replace("\\", "/")
            figures += (
                "\\begin{figure}[H]\n"
                "  \\centering\n"
                f"  \\includegraphics[width=0.85\\textwidth, keepaspectratio]{{{img}}}\n"
                f"  \\caption{{Figure {i+1}}}\n"
                "\\end{figure}\n"
            )

    # Question
    question_section = ""
    if question:
        question_section = (
            "\\section{Problem}\n"
            "\\begin{tcolorbox}[colback=gray!3, colframe=Accent, title=Question]\n"
            f"{fix_latex_spacing(question)}\n"
            "\\end{tcolorbox}\n"
        )

    # ── Solution Steps (NEW) ─────────────────────────────────────────
    steps_section = ""
    parsed_steps = parse_steps(steps)
    if parsed_steps:
        step_items = []
        for i, step in enumerate(parsed_steps, 1):
            # Step content is raw LaTeX — do NOT escape (it contains
            # \begin{itemize}, \textbf{}, \[...\], etc.)
            # But fix a common issue: single-backslash spacing commands
            # like \[4pt] or \[2cm] should be \\[4pt] or \\[2cm]
            # (these occur in cases/aligned envs after line breaks)
            content_raw = fix_latex_spacing(step['content'])
            # Title may contain inline math $...$ — use tex_escape
            title_escaped = tex_escape(step['title'])
            step_items.append(
                "\\begin{tcolorbox}[colback=blue!2, colframe=blue!30!black,\n"
                f"    title={{\\bfseries Step {i}: {title_escaped}}}, fonttitle=\\bfseries]\n"
                f"{content_raw}\n"
                "\\end{tcolorbox}"
            )
        steps_section = (
            "\\section{Solution Steps}\n"
            "\\setlength{\\parskip}{6pt}\n"
            + "\n\\vspace{4pt}\n".join(step_items) +
            "\n"
        )

    # ── Method / Analysis Section ─────────────────────────────────────
    analysis_section = ""
    if analysis:
        analysis_section = (
            "\\section{Solution Method}\n"
            "\\begin{tcolorbox}[colback=green!2, colframe=green!40!black, "
            "title=Analytical Approach, fonttitle=\\bfseries]\n"
            f"{fix_latex_spacing(analysis)}\n"
            "\\end{tcolorbox}\n"
        )

    # ── Result (smart line breaking for long formulas) ──────────────
    result_tex_clean = (result_tex or "").strip()
    if result_tex_clean:
        # Remove outer $$ or \[\] wrappers — we'll provide our own
        inner_tex = result_tex_clean
        inner_tex = re.sub(r'^\$\$?\s*', '', inner_tex)
        inner_tex = re.sub(r'\s*\$?\$\s*$', '', inner_tex)
        inner_tex = re.sub(r'^\\\[\s*', '', inner_tex)
        inner_tex = re.sub(r'\s*\\\]$', '', inner_tex)

        # ── Smart break insertion ─────────────────────────────────
        # Estimate whether breaking is needed (quick length check)
        needs_breaking = (len(inner_tex) > 120 or
                          inner_tex.count('\\\\') > 0 or
                          sum(1 for _ in inner_tex) > 200)

        if needs_breaking:
            # Apply smart breaking with a calibrated max line width
            # (~155 weight units ≈ 418 pt textwidth at 11pt)
            broken_tex = smart_break_math(inner_tex, max_width=155)
        else:
            broken_tex = inner_tex

        # Choose math environment
        if '\\\\' in broken_tex:
            env = 'align*'
        else:
            env = 'align*'  # single line works fine in align* too

        result_display = (
            "\\begin{tcolorbox}[colback=blue!2, colframe=blue!35!black, "
            "title=Mathematical Result, fonttitle=\\bfseries]\n"
            f"\\begin{{{env}}}\n"
            "\\displaystyle " + broken_tex + "\n"
            f"\\end{{{env}}}\n"
            "\\end{tcolorbox}\n"
        )
    else:
        result_display = "\\texttt{(no result)}"

    # Raw output
    raw_section = ""
    if result_raw.strip():
        raw_section = (
            "\\section{Raw Output}\n"
            "\\begin{tcolorbox}[colback=gray!2, colframe=gray!50, "
            "title=Plain Text Output]\n"
            "\\begin{verbatim}\n"
            f"{result_raw.strip()}\n"
            "\\end{verbatim}\n"
            "\\end{tcolorbox}\n"
        )

    # Notes
    notes_section = ""
    if notes:
        notes_section = (
            "\\section{Notes}\n"
            "\\begin{tcolorbox}[colback=yellow!5, colframe=yellow!60!black, "
            "title=Analysis Notes]\n"
            f"{fix_latex_spacing(notes)}\n"
            "\\end{tcolorbox}\n"
        )

    tex = r"""% !TEX program = xelatex
\documentclass[11pt,a4paper,fleqn]{article}
\usepackage[no-math]{xeCJK}
\setCJKmainfont{SimSun}[BoldFont=SimHei, ItalicFont=KaiTi]
\setCJKsansfont{SimHei}
\setCJKmonofont{KaiTi}
\usepackage{amsmath, amssymb, amsfonts, mathtools}
\usepackage{bm}
\usepackage{geometry}
\geometry{a4paper, margin=2.5cm, headheight=14pt}
\usepackage[svgnames]{xcolor}
\definecolor{Accent}{HTML}{2B579A}
\definecolor{CodeBg}{HTML}{F4F4F4}
\definecolor{CodeFrame}{HTML}{CCCCCC}
\definecolor{DarkText}{HTML}{1A1A2E}
\definecolor{GrayText}{HTML}{666666}
\usepackage{graphicx}
\usepackage{float}
\usepackage{listings}
\lstdefinelanguage{Wolfram}{
    keywords={Module,Block,With,If,Do,For,While,Table,Map,Apply,
              Function,Set,SetDelayed,Integrate,D,Solve,NSolve,
              DSolve,Plot,Plot3D,Export,Import,Expand,Factor,
              Simplify,FullSimplify,Limit,Series,Sum,Product,
              Print,Return,ListPlot,ContourPlot,Manipulate},
    keywordstyle=\color{blue!60!black}\bfseries,
    commentstyle=\color{green!50!black}\itshape,
    stringstyle=\color{red!60!black},
    morecomment=[l]{(*}, morecomment=[s]{(*}{*)},
    morestring=[b]", morestring=[b]', sensitive=true,
}
\lstset{
    language=Wolfram, basicstyle=\ttfamily\small,
    backgroundcolor=\color{CodeBg}, frame=single, framerule=0.6pt,
    rulecolor=\color{CodeFrame}, numbers=left, numberstyle=\tiny\color{gray},
    numbersep=6pt, breaklines=true, breakatwhitespace=false,
    showstringspaces=false, tabsize=2, captionpos=b,
    aboveskip=1em, belowskip=1em,
}
\usepackage[most]{tcolorbox}
\tcbset{boxsep=3pt, left=8pt, right=8pt, top=6pt, bottom=6pt, arc=2pt, boxrule=0.6pt}
\usepackage{fancyhdr}
\pagestyle{fancy}
\fancyhf{}
\fancyhead[L]{\small\color{GrayText} _HDR_TITLE_}
\fancyhead[R]{\small\color{GrayText} Wolfram \, Mathematica \, Report}
\fancyfoot[C]{\small\color{GrayText} ---\ \thepage\ ---}
\renewcommand{\headrulewidth}{0.4pt}
\usepackage{hyperref}
\hypersetup{pdftitle={_PDF_TITLE_}, pdfauthor={Wolfram Mathematica Agent},
    colorlinks=true, linkcolor=Accent, urlcolor=Accent, citecolor=Accent}
\usepackage{titlesec}
\titleformat{\section}{\normalfont\Large\bfseries\color{Accent}}{\thesection}{1em}{}
\titlespacing*{\section}{0pt}{16pt}{8pt}

% ── Long formula support ─────────────────────────────────────────
\allowdisplaybreaks
\setlength{\mathindent}{0pt}

\begin{document}
\begin{titlepage}
\thispagestyle{empty}
\vspace*{3cm}
\begin{center}
{\Huge\bfseries\color{DarkText} _TITLE_}\\[0.8cm]
{\Large\color{GrayText} Wolfram \, Mathematica \, Computation \, Report}\\[2cm]
\vspace{2cm}
\begin{tcolorbox}[width=0.85\textwidth, colback=white, colframe=gray!30,
    title=Report Information, fonttitle=\bfseries]
\begin{tabular}{@{}p{3.5cm} p{10cm}@{}}
    \textbf{Title}     & _TITLE_ \\[4pt]
    \textbf{Generated} & _TS_ \\[4pt]
    \textbf{Compiler}  & Xe\LaTeX \\[4pt]
\end{tabular}
\end{tcolorbox}
\end{center}
\vfill
\end{titlepage}

_QUESTION_SECTION_
_ANALYSIS_SECTION_
_STEPS_SECTION_
\section{Mathematica Code}
\begin{lstlisting}[caption={Computation Code}]
_CODE_
\end{lstlisting}
\section{Computation Result}
_RESULT_DISPLAY_
_RAW_OUTPUT_
_FIGURES_
_NOTES_
\end{document}
"""

    tex = (tex
        .replace("_HDR_TITLE_", title_safe[:55])
        .replace("_PDF_TITLE_", title_safe)
        .replace("_TITLE_", title_safe)
        .replace("_TS_", ts)
        .replace("_QUESTION_SECTION_", question_section)
        .replace("_ANALYSIS_SECTION_", analysis_section)
        .replace("_STEPS_SECTION_", steps_section)
        .replace("_CODE_", tex_escape(code))
        .replace("_RESULT_DISPLAY_", result_display)
        .replace("_RAW_OUTPUT_", raw_section)
        .replace("_FIGURES_", figures)
        .replace("_NOTES_", notes_section)
    )
    return tex


def compile_latex(tex_path, out_pdf):
    xelatex = find_xelatex()
    tex_dir = os.path.dirname(os.path.abspath(tex_path))
    # Use only the filename (not full path) since cwd=tex_dir.
    # Also pass -output-directory to guarantee output location.
    tex_fname = os.path.basename(tex_path)

    for run_idx in range(2):
        result = subprocess.run(
            [xelatex, "-interaction=nonstopmode",
             "-output-directory=" + tex_dir, tex_fname],
            capture_output=True, text=True, cwd=tex_dir, timeout=120,
        )
        # Check for fatal errors
        if result.returncode != 0:
            stderr_lines = result.stderr.split('\n') if result.stderr else []
            fatal = any('Fatal' in l or 'fatal' in l for l in stderr_lines)
            if fatal:
                return False, f"XeLaTeX fatal error on run {run_idx+1}"

    base = os.path.splitext(os.path.basename(tex_path))[0]
    local_pdf = os.path.join(tex_dir, base + ".pdf")

    if not os.path.isfile(local_pdf):
        return False, f"PDF not found at {local_pdf}"

    pdf_size = os.path.getsize(local_pdf)
    if pdf_size <= 500:
        return False, f"PDF too small: {pdf_size} bytes at {local_pdf}"

    # Ensure output directory exists
    out_dir = os.path.dirname(out_pdf)
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)

    try:
        shutil.copy2(local_pdf, out_pdf)
    except OSError as e:
        return False, f"Failed to copy PDF to {out_pdf}: {e}"

    # Clean aux files
    for ext in [".aux", ".log", ".out", ".toc"]:
        aux_file = os.path.join(tex_dir, base + ext)
        if os.path.isfile(aux_file):
            try:
                os.unlink(aux_file)
            except OSError:
                pass

    return True, out_pdf


def main():
    parser = argparse.ArgumentParser(description="Standalone PDF export — reads all content from a JSON config file")
    parser.add_argument("--config", required=True,
                        help="Path to JSON config file (all content fields; no shell escaping issue)")
    parser.add_argument("--output", "-o", default="",
                        help="Optional output PDF path (overrides auto-generated name)")

    args = parser.parse_args()

    config_path = args.config
    if not os.path.isfile(config_path):
        print(json.dumps({"success": False, "error": f"Config file not found: {config_path}"},
                         ensure_ascii=False, indent=2))
        sys.exit(1)

    with open(config_path, "r", encoding="utf-8") as f:
        cfg = json.load(f)

    title       = cfg.get("title", "")
    if not title:
        print(json.dumps({"success": False, "error": "JSON config must contain a non-empty \"title\" field"},
                         ensure_ascii=False, indent=2))
        sys.exit(1)

    code        = cfg.get("code", "")
    result_tex  = cfg.get("result_tex", "")
    result_raw  = cfg.get("result_raw", "")
    question    = cfg.get("question", "")
    steps       = cfg.get("steps", "")
    analysis    = cfg.get("analysis", "")
    notes       = cfg.get("notes", "")
    images      = cfg.get("images", "")

    os.makedirs(OUTPUT_DIR, exist_ok=True)

    out_override = args.output or cfg.get("output", "")
    if out_override:
        out_pdf = out_override
    else:
        safe_title = re.sub(r'[<>:"/\\|?*]', '_', title)[:60].strip()
        ts = datetime.now().strftime("%Y%m%d_%H%M%S")
        out_pdf = os.path.join(OUTPUT_DIR, f"{safe_title}_{ts}.pdf")

    image_paths = [p.strip() for p in images.split(",") if p.strip()] if images else []

    work_dir = tempfile.mkdtemp(prefix="pdf_standalone_")
    tex_path = os.path.join(work_dir, "report.tex")

    tex_content = build_latex(
        title, code, result_tex, result_raw,
        question, notes, steps, analysis, image_paths,
    )

    with open(tex_path, "w", encoding="utf-8") as f:
        f.write(tex_content)

    success, pdf_path = compile_latex(tex_path, out_pdf)

    # Cleanup
    try:
        shutil.rmtree(work_dir, ignore_errors=True)
    except OSError:
        pass

    if success:
        result = {"success": True, "pdf_file": pdf_path}
    else:
        result = {"success": False, "pdf_file": None, "error": "XeLaTeX compilation failed"}

    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
