#!/usr/bin/env python3
"""
Convert a lightweight Markdown document to PDF using macOS textutil.
This avoids external dependencies while producing a Preview-friendly PDF.
"""

from __future__ import annotations

import html
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path


HEADING_STYLES = {
    1: "font-size: 22px; margin-top: 28px; margin-bottom: 12px;",
    2: "font-size: 18px; margin-top: 24px; margin-bottom: 10px;",
    3: "font-size: 16px; margin-top: 20px; margin-bottom: 8px;",
}


def markdown_to_html(markdown: str) -> str:
    html_lines: list[str] = [
        "<!DOCTYPE html>",
        "<html>",
        "<head>",
        '<meta charset="utf-8">',
        "<style>",
        "body { font-family: -apple-system, BlinkMacSystemFont, 'Helvetica Neue', Helvetica, Arial, sans-serif;"
        " font-size: 12pt; margin: 48px 60px; line-height: 1.5; color: #131313; }",
        "h1, h2, h3 { font-weight: 600; }",
        "p { margin: 10px 0; }",
        "ul, ol { margin: 8px 0 8px 24px; }",
        "li { margin: 4px 0; }",
        "strong { font-weight: 600; }",
        "</style>",
        "</head>",
        "<body>",
    ]

    in_ul = False
    in_ol = False

    def close_lists() -> None:
        nonlocal in_ul, in_ol
        if in_ul:
            html_lines.append("</ul>")
            in_ul = False
        if in_ol:
            html_lines.append("</ol>")
            in_ol = False

    numbered_pattern = re.compile(r"^(\d+)\.\s+(.*)")

    for raw_line in markdown.splitlines():
        line = raw_line.rstrip()
        stripped = line.strip()

        if not stripped:
            close_lists()
            html_lines.append("<p>&nbsp;</p>")
            continue

        if stripped.startswith("#"):
            close_lists()
            level = len(stripped) - len(stripped.lstrip("#"))
            level = max(1, min(level, 3))
            text = stripped[level:].strip()
            html_lines.append(
                f'<h{level} style="{HEADING_STYLES[level]}" >{html.escape(text)}</h{level}>'
            )
            continue

        match = numbered_pattern.match(stripped)
        if match:
            if not in_ol:
                close_lists()
                html_lines.append("<ol>")
                in_ol = True
            html_lines.append(f"<li>{html.escape(match.group(2))}</li>")
            continue

        if stripped.startswith("- "):
            if not in_ul:
                close_lists()
                html_lines.append("<ul>")
                in_ul = True
            html_lines.append(f"<li>{html.escape(stripped[2:].strip())}</li>")
            continue

        close_lists()
        html_lines.append(f"<p>{html.escape(stripped)}</p>")

    close_lists()
    html_lines.extend(["</body>", "</html>"])
    return "\n".join(html_lines)


def convert_to_pdf(markdown_path: Path, output_path: Path) -> None:
    html_content = markdown_to_html(markdown_path.read_text(encoding="utf-8"))

    with tempfile.NamedTemporaryFile("w", suffix=".html", delete=False, encoding="utf-8") as tmp:
        tmp_path = Path(tmp.name)
        tmp.write(html_content)

    try:
        subprocess.run(
            [
                "textutil",
                "-convert",
                "pdf",
                str(tmp_path),
                "-output",
                str(output_path),
            ],
            check=True,
        )
    finally:
        try:
            os.remove(tmp_path)
        except OSError:
            pass


def main() -> int:
    if len(sys.argv) != 3:
        print("Usage: make_pdf.py <input.md> <output.pdf>", file=sys.stderr)
        return 1

    src = Path(sys.argv[1])
    dst = Path(sys.argv[2])

    if not src.exists():
        print(f"Input file not found: {src}", file=sys.stderr)
        return 1

    convert_to_pdf(src, dst)
    print(f"Wrote {dst}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
