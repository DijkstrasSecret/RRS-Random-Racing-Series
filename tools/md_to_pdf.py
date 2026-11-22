"""Convert a Markdown design doc to a styled PDF via headless Edge/Chrome.

Usage: python tools/md_to_pdf.py docs/RRS_Design_Concept.md
"""
import os
import subprocess
import sys
from pathlib import Path

import markdown

CSS = """
@page { size: A4; margin: 18mm 16mm 18mm 16mm; }
* { box-sizing: border-box; }
body { font-family: 'Segoe UI', Arial, sans-serif; font-size: 10.5pt; line-height: 1.5;
       color: #1d1f24; margin: 0; }
h1 { font-size: 30pt; margin: 0 0 4px; color: #c8102e; letter-spacing: -0.5px; }
h1 + h3 { margin-top: 0; color: #444; font-weight: 600; }
h2 { font-size: 15pt; color: #fff; background: #1d1f24; padding: 6px 10px; margin: 26px 0 10px;
     border-left: 6px solid #c8102e; page-break-after: avoid; }
h3 { font-size: 12pt; color: #c8102e; margin: 16px 0 6px; page-break-after: avoid; }
p, li { margin: 4px 0; }
strong { color: #000; }
hr { border: 0; border-top: 2px solid #c8102e; margin: 14px 0; }
table { border-collapse: collapse; width: 100%; margin: 8px 0 12px; font-size: 9.5pt;
        page-break-inside: avoid; }
th { background: #2b2e35; color: #fff; text-align: left; padding: 5px 7px; }
td { border-bottom: 1px solid #ddd; padding: 5px 7px; vertical-align: top; }
tr:nth-child(even) td { background: #f5f5f7; }
code { font-family: Consolas, monospace; font-size: 9pt; background: #f0f0f3; padding: 1px 4px;
       border-radius: 3px; }
pre { background: #1d1f24; color: #e8e8e8; padding: 10px 12px; border-radius: 4px;
      font-size: 8.5pt; line-height: 1.3; overflow: hidden; page-break-inside: avoid; }
pre code { background: none; color: inherit; padding: 0; }
em { color: #555; }
"""


def find_browser() -> str:
    candidates = [
        os.path.expandvars(r"%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe"),
        os.path.expandvars(r"%ProgramFiles%\Microsoft\Edge\Application\msedge.exe"),
        os.path.expandvars(r"%ProgramFiles%\Google\Chrome\Application\chrome.exe"),
    ]
    for c in candidates:
        if os.path.exists(c):
            return c
    sys.exit("No Edge/Chrome found for PDF rendering.")


def main() -> None:
    src = Path(sys.argv[1]).resolve()
    html_body = markdown.markdown(src.read_text(encoding="utf-8"),
                                  extensions=["tables", "fenced_code", "sane_lists"])
    html = (f"<!doctype html><html><head><meta charset='utf-8'><title>{src.stem}</title>"
            f"<style>{CSS}</style></head><body>{html_body}</body></html>")
    html_path = src.with_suffix(".html")
    pdf_path = src.with_suffix(".pdf")
    html_path.write_text(html, encoding="utf-8")
    subprocess.run([find_browser(), "--headless=new", "--disable-gpu", "--no-pdf-header-footer",
                    f"--print-to-pdf={pdf_path}", html_path.as_uri()], check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    html_path.unlink()
    print(f"Wrote {pdf_path}")


if __name__ == "__main__":
    main()
