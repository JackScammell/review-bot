"""Unit tests for the pure helpers in scripts/review_bot.py.

No network, no API key and no third-party packages: review_bot.py imports
`anthropic` only inside the functions that call the API.
Run with: python3 -m unittest discover -s tests -v
"""
import os
import re
import sys
import tempfile
import types
import unittest
from pathlib import Path

# review_bot.py reads these at import time.
os.environ.setdefault("TIER", "single")
os.environ.setdefault("PR", "1")
os.environ.setdefault("REPO", "example/repo")
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scripts"))

import review_bot as rb  # noqa: E402

ZWSP = "\u200b"  # zero-width space, written as an escape so editors can't strip it
ROOT = Path(__file__).resolve().parent.parent
BASE = ["grumpy-security-nag", "grumpy-code-reviewer"]


def ctx_for(files, diff=""):
    """Minimal context for choose_panel: files are (path, changed lines)."""
    return {"meta": {"files": [{"path": p, "additions": n, "deletions": 0} for p, n in files]},
            "diff": diff}


class CommentableLines(unittest.TestCase):
    DIFF = "\n".join([
        "diff --git a/app.py b/app.py",
        "index 1111111..2222222 100644",
        "--- a/app.py",
        "+++ b/app.py",
        "@@ -1,3 +1,4 @@",
        " first",
        "-removed",
        "+replacement",
        "+added",
        " last",
        "@@ -20,2 +21,2 @@",
        " context",
        "\\ No newline at end of file",
        "diff --git a/gone.py b/gone.py",
        "--- a/gone.py",
        "+++ /dev/null",
        "@@ -1,1 +0,0 @@",
        "-bye",
    ])

    def test_added_and_context_lines_count_removed_lines_do_not(self):
        lines = rb.commentable_lines(self.DIFF)
        self.assertEqual(
            {l for p, l in lines if p == "app.py"}, {1, 2, 3, 4, 21})

    def test_deleted_file_adds_nothing(self):
        self.assertFalse({p for p, _ in rb.commentable_lines(self.DIFF)} - {"app.py"})


class ChoosePanel(unittest.TestCase):
    def test_docs_only_adds_documentation_reviewer(self):
        self.assertEqual(rb.choose_panel(ctx_for([("README.md", 400)])),
                         BASE + ["grumpy-documentation-pedant"])

    def test_small_change_gets_the_floor_only(self):
        self.assertEqual(rb.choose_panel(ctx_for([("app.py", 49)])), BASE)

    def test_lockfile_lines_do_not_count(self):
        ctx = ctx_for([("package-lock.json", 5000), ("app.py", 10)])
        self.assertEqual(rb.choose_panel(ctx), BASE)

    def test_personal_data_words_in_added_lines_add_privacy(self):
        ctx = ctx_for([("app.py", 5)], diff="+send_to(user.email)\n")
        self.assertIn("grumpy-privacy-paranoid", rb.choose_panel(ctx))

    def test_medium_code_change(self):
        self.assertEqual(rb.choose_panel(ctx_for([("app.py", 60)])),
                         BASE + ["grumpy-standards-enforcer", "grumpy-testing-tyrant"])

    def test_large_mixed_change_has_no_duplicates(self):
        ctx = ctx_for([("db/migrations/1.sql", 200), ("app.py", 200), ("README.md", 10),
                       (".github/workflows/ci.yml", 10)], diff="+select 1\n+email\n")
        panel = rb.choose_panel(ctx)
        self.assertEqual(len(panel), len(set(panel)))
        for name in ("grumpy-performance-troll", "grumpy-architecture-skeptic",
                     "grumpy-maintainability-curmudgeon", "grumpy-budget-hawk"):
            self.assertIn(name, panel)

    # One case per row of the council selection table in docs/configuration.md.
    def panel(self, files, diff=""):
        return rb.choose_panel(ctx_for(files, diff))

    def test_each_personal_data_word_adds_privacy(self):
        for word in ("email", "phone", "address", "postcode", "date of birth", "dob",
                     "national insurance", "ni number", "surname", "forename", "uln", "learner"):
            with self.subTest(word=word):
                self.assertIn("grumpy-privacy-paranoid", self.panel([("app.py", 5)], f"+{word}\n"))

    def test_personal_data_words_in_removed_lines_do_not_count(self):
        self.assertNotIn("grumpy-privacy-paranoid", self.panel([("app.py", 5)], "-email\n"))

    def test_requirements_files_are_not_docs_only(self):
        for files in ([("requirements.txt", 10)], [("app/requirements.txt", 10)],
                      [("Requirements.txt", 10)], [("requirements/base.txt", 10)],
                      [("requirements.txt", 10), ("README.md", 10)]):
            with self.subTest(files=files):
                self.assertEqual(self.panel(files), BASE)

    def test_docs_only_includes_txt_and_rst(self):
        self.assertEqual(self.panel([("notes.txt", 60), ("guide.rst", 60)]),
                         BASE + ["grumpy-documentation-pedant"])

    def test_documentation_pedant_joins_a_mixed_change_from_50_lines(self):
        self.assertIn("grumpy-documentation-pedant", self.panel([("app.py", 45), ("README.md", 5)]))
        self.assertNotIn("grumpy-documentation-pedant", self.panel([("app.py", 44), ("README.md", 5)]))

    def test_standards_enforcer_joins_at_50_lines(self):
        self.assertEqual(self.panel([("data.json", 50)]), BASE + ["grumpy-standards-enforcer"])

    def test_file_type_members(self):
        cases = {
            "grumpy-accessibility-auditor": ["a.html", "a.css", "a.scss", "a.tsx", "a.jsx", "a.vue",
                                             "a.cshtml", "a.razor", "a.blade.php", "templates/x",
                                             "views/x"],
            "grumpy-i18n-nitpicker": ["locale/en.json", "locales/x", "lang/x", "i18n/x", "a.resx"],
            "grumpy-performance-troll": ["a.sql", "migrations/x", "db/migration/x"],
            "grumpy-budget-hawk": [".github/workflows/x", "Dockerfile", "main.tf",
                                   "appsettings.json", "a.yml", "a.yaml"],
            "grumpy-testing-tyrant": ["a.cs", "a.py", "a.ps1", "a.psm1", "a.ts", "a.js", "a.php", "a.sql"],
            "grumpy-architecture-skeptic": ["a.csproj", "a.sln", "package.json", "requirements-dev.txt",
                                            "pyproject.toml", "composer.json"],
        }
        for member, paths in cases.items():
            for path in paths:
                with self.subTest(member=member, path=path):
                    self.assertIn(member, self.panel([(path, 60)]))
            with self.subTest(member=member, path="data.json"):
                self.assertNotIn(member, self.panel([("data.json", 60)]))

    def test_performance_troll_joins_on_query_words(self):
        for diff in ("+SELECT id\n", "+x JOIN y\n", "+ORDER BY a\n"):
            with self.subTest(diff=diff):
                self.assertIn("grumpy-performance-troll", self.panel([("data.json", 60)], diff))

    def test_size_thresholds(self):
        for member, limit in (("grumpy-maintainability-curmudgeon", 150),
                              ("grumpy-performance-troll", 200),
                              ("grumpy-architecture-skeptic", 300)):
            with self.subTest(member=member):
                self.assertNotIn(member, self.panel([("data.json", limit)]))
                self.assertIn(member, self.panel([("data.json", limit + 1)]))


class DocumentedDefaults(unittest.TestCase):
    """The defaults in docs/configuration.md must match both workflow files."""

    def setUp(self):
        self.review = (ROOT / ".github/workflows/review.yml").read_text()
        self.standalone = (ROOT / "examples/standalone.yml").read_text()
        self.doc = (ROOT / "docs/configuration.md").read_text()

    def review_default(self, name):
        m = re.search(rf"^      {name}:\n(?:        .*\n)*?        default: \"?([^\"\n]*)\"?$",
                      self.review, re.M)
        self.assertIsNotNone(m, f"no default for {name} in review.yml")
        return m.group(1)

    def standalone_env(self, name):
        m = re.search(rf"^  {name}: \"?([^\"\n]*)\"?$", self.standalone, re.M)
        self.assertIsNotNone(m, f"no {name} in standalone.yml")
        return m.group(1)

    def test_docs_match_review_workflow(self):
        for name in ("bot_ref", "monthly_budget_usd", "single_model", "council_model",
                     "council_ref", "large_pr_lines"):
            with self.subTest(input=name):
                self.assertIn(f"| `{name}` | `{self.review_default(name)}` |", self.doc)

    def test_standalone_matches_review_workflow(self):
        for env, name in (("BOT_REF", "bot_ref"), ("SINGLE_MODEL", "single_model"),
                          ("COUNCIL_MODEL", "council_model"), ("COUNCIL_REF", "council_ref"),
                          ("LARGE_PR_LINES", "large_pr_lines")):
            with self.subTest(env=env):
                self.assertEqual(self.standalone_env(env), self.review_default(name))

    def test_risky_path_pattern_matches_plan_sh(self):
        plan = (ROOT / "scripts/plan.sh").read_text()
        code = re.search(r"^RISK_RE='([^']*)'$", plan, re.M).group(1)
        self.assertIn(f"\n{code}\n", self.doc)

    def test_budget_ladder_matches_plan_sh(self):
        plan = (ROOT / "scripts/plan.sh").read_text()
        hold, single, council = re.findall(r'ge "\$PCT" (0\.\d+)', plan)
        pace = re.search(r'ge "\$PACE" (\d+\.\d+)', plan).group(1)
        pct = lambda x: f"{round(float(x) * 100)}%"
        self.assertIn(f"| {pct(hold)} or more spent | No review.", self.doc)
        self.assertIn(f"| {pct(single)} or more spent | Single reviews only", self.doc)
        self.assertIn(f"| {pct(council)} or more spent, **or** pace {pace} or more |", self.doc)
        self.assertIn(f"| Under {pct(council)} spent and pace under {pace} |", self.doc)
        # The reasons plan.sh posts repeat two of the thresholds.
        self.assertIn(f"({pct(single)}+ of budget used)", plan)
        self.assertIn(f"(budget over {pct(council)} or ahead of pace)", plan)

    def test_every_checkout_drops_the_token(self):
        for name in (".github/workflows/review.yml", ".github/workflows/ci.yml",
                     "examples/standalone.yml"):
            text = (ROOT / name).read_text()
            blocks = re.split(r"\n\s*- (?=[\w-]+:)", text)  # every list item that starts a mapping
            checkouts = [b for b in blocks if "actions/checkout@" in b]
            self.assertTrue(checkouts, name)
            for block in checkouts:
                with self.subTest(file=name, checkout=block.strip().splitlines()[0]):
                    self.assertRegex(block, r"persist-credentials: false")

    def test_documented_limits_match_the_code(self):
        def row(label):
            m = re.search(rf"^\| {re.escape(label)} \| ([^|]+) \|$", self.doc, re.M)
            self.assertIsNotNone(m, f"no row '{label}' in configuration.md")
            return m.group(1)

        def number(text):
            return int(re.match(r"[\d,]+", text).group().replace(",", ""))

        def prompt_cap(name):
            text = (ROOT / "prompts" / name).read_text()
            return int(re.search(r"at most (\d+) findings", text, re.I).group(1))

        record = (ROOT / "scripts/record-cost.sh").read_text()
        self.assertEqual(number(row("Diff sent to the model")), rb.MAX_DIFF_CHARS)
        self.assertEqual(number(row("Contents of one changed file")), rb.MAX_FILE_CHARS)
        self.assertEqual(number(row("Contents of all changed files")), rb.MAX_FILES_CHARS)
        self.assertEqual(number(row("Findings in a single review")), prompt_cap("single.md"))
        self.assertEqual(number(row("Findings per council member")), prompt_cap("council-member.md"))
        self.assertEqual(number(row("Findings the chair keeps")), prompt_cap("council-synthesis.md"))
        self.assertIn("max_workers=" + row("Council members running at once"),
                      (ROOT / "scripts/review_bot.py").read_text())
        single, council = re.findall(r"\$(\d+\.\d+)", row("Cost recorded when a run reports none"))
        self.assertIn(f"single) COST={single}", record)
        self.assertIn(f"*) COST={council}", record)


class NoMentions(unittest.TestCase):
    def test_handles_are_broken(self):
        self.assertEqual(rb.no_mentions("thanks @someone"), f"thanks @{ZWSP}someone")

    def test_email_like_text_is_also_broken(self):
        self.assertEqual(rb.no_mentions("a@b.com"), f"a@{ZWSP}b.com")

    def test_lone_at_sign_is_left_alone(self):
        self.assertEqual(rb.no_mentions("meet @ noon"), "meet @ noon")


def fake_response(model, **tokens):
    usage = types.SimpleNamespace(input_tokens=None, output_tokens=None,
                                  cache_creation_input_tokens=None, cache_read_input_tokens=None)
    for k, v in tokens.items():
        setattr(usage, k, v)
    return types.SimpleNamespace(model=model, usage=usage)


class Spend(unittest.TestCase):
    def test_known_model_uses_its_prices(self):
        s = rb.Spend()
        s.add(fake_response("claude-sonnet-5-5", input_tokens=1_000_000, output_tokens=100_000))
        self.assertAlmostEqual(s.usd, 2.00 + 1.00)

    def test_unknown_model_is_priced_as_the_dearest(self):
        s = rb.Spend()
        s.add(fake_response("some-future-model", input_tokens=1_000_000))
        self.assertAlmostEqual(s.usd, rb.PRICES["claude-opus-5-5"][0])

    def test_missing_token_counts_are_zero(self):
        s = rb.Spend()
        s.add(fake_response("claude-sonnet-5-5"))
        self.assertEqual(s.usd, 0.0)


class Render(unittest.TestCase):
    def setUp(self):
        saved = rb.SPEND
        self.addCleanup(setattr, rb, "SPEND", saved)
        rb.SPEND = rb.Spend()
        self.ctx = {"round": 2, "meta": {"headRefOid": "abc1234def"}}

    def test_layout_marker_and_scrubbing(self):
        result = {"verdict": "APPROVE-WITH-NOTES", "summary": "Ask @someone first.",
                  "findings": [
                      {"severity": "Low", "path": "app.py", "line": 0, "title": "T", "detail": "D"},
                      {"severity": "Medium", "path": "app.py", "line": 7, "title": "U", "detail": "E"},
                  ]}
        body = rb.render(result, self.ctx, "single review")
        self.assertIn("round 2", body)
        self.assertIn("| Low | `app.py` |", body)
        self.assertIn("| Medium | `app.py:7` |", body)
        self.assertIn(f"@{ZWSP}someone", body)
        self.assertIn(f"{rb.MARKER} head=abc1234def tier={rb.TIER} round=2 -->", body)


class Persona(unittest.TestCase):
    def test_front_matter_is_stripped(self):
        with tempfile.TemporaryDirectory() as d:
            (Path(d) / "agents").mkdir()
            (Path(d) / "agents" / "grumpy-x.md").write_text("---\nname: x\n---\n\nBe grumpy.\n")
            old, rb.COUNCIL_DIR = rb.COUNCIL_DIR, Path(d)
            try:
                self.assertEqual(rb.persona("grumpy-x"), "Be grumpy.")
            finally:
                rb.COUNCIL_DIR = old


if __name__ == "__main__":
    unittest.main()
