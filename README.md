# HKPFS candidate review tool

Open MATLAB in this folder and run:

```matlab
HKPFS_GUI_Tool_Optimized
```

This loads `Test_file_2025.xlsx` beside the program. The workbook contains **42 entirely fictional profiles**, including new names, application identifiers, institutions, academic records, publications and other narrative information. There is no real-to-fictional identity lookup. The original header layout and row positions are retained. Source author/provenance metadata has been removed.

Keep these four program files together:

- `HKPFS_GUI_Tool_Optimized.m`: review and comparison windows.
- `HKPFS_load_candidates.m`: independent Excel import and validation.
- `HKPFS_rank_candidates.m`: independent rating-group ranking.
- `HKPFS_export_ranking.m`: summary and complete-profile export.

The code targets MATLAB R2020b or newer with desktop graphics. No additional toolbox or Microsoft Excel installation is needed for `.xlsx` files. MATLAB execution could not be verified: the installed R2025a could not contact the organization's license server (MathWorks licensing error 15). The regression suite and GUI require validation after license access is restored.

## Review workflow

1. Assign each candidate an integer rating from 1 to 5. Selecting a rating advances to the next candidate. Use **Previous** and **Next** to revisit records; the selected rating is highlighted.
2. Add reviewer notes if useful. **Save progress** saves ratings and notes to a `.mat` file. **Load progress** restores them only when the candidate data and row order match the current workbook. Save again after making further changes. Progress is not saved automatically.
3. **Start ranking** becomes available after every candidate is rated. Candidates are grouped from rating 5 down to 1. Choose which of two equally rated candidates should rank higher.
4. For equal preference, choose A to preserve input order. The final list still assigns distinct sequential ranks. Closing either review window cancels that phase; no partial final ranking is exported. A saved ratings file can be reloaded, but pairwise comparison choices must be repeated after cancellation.
5. Choose an output `.xlsx` filename. The **Ranking** sheet contains the ranking, original identifiers, reviewer rating, notes and source location. **Candidate details** includes all imported profile information. The source research-potential score is shown separately and never used as the reviewer's rating.

With arguments, the tool can return the complete ranked table and use a specified output path:

```matlab
ranked = HKPFS_GUI_Tool_Optimized('Applicants.xlsx', 'Final_HKPFS_Ranking.xlsx');
ranked = HKPFS_GUI_Tool_Optimized('Applicants.xlsx', 'Final_HKPFS_Ranking.xlsx', ...
    'Sheet', 'Applicants', 'HeaderRow', 10);
```

An explicitly supplied output path replaces an existing file at that path after both sheets have been written successfully. A final output path must differ from the input path. Cancelling Save As still returns the completed `ranked` table when an output variable was requested.

## Spreadsheet layouts

- Columns can appear in any order, and the table can start below introductory text or to the right of blank columns. Import is anchored at Excel A1 so reported source row numbers are physical Excel rows.
- The loader scans all worksheets. If several contain candidate tables, the GUI asks you to select one. Standalone import requires the `Sheet` option in that case.
- A single header row must contain **Name** and at least one of **HKPFS no.** or **Application no.** Case, spaces, line breaks and punctuation are ignored. Aliases include `Applicant Name`, `Candidate Name`, `Full Name`, `HKPFS ID`, `HKPFS Number`, `Application ID`, and `Application Number`.
- The supplied workbook's vertically merged headers are supported because their labels start on one row. Headers whose identifying labels are split across multiple different rows must first be consolidated into one header row.
- Blank rows and repeated headers with the same layout are skipped. Optional columns can be absent. A missing Sequence receives `row-<Excel row number>`; that candidate is retained.
- Each candidate needs a name and at least one identifier. Missing identity fields, duplicate nonblank application/HKPFS identifiers, and duplicate recognized headers produce an actionable error instead of an unreliable ranking. Numeric IDs that have already lost leading zeros in Excel cannot be reconstructed; store identifiers as text.
- Previously omitted degree/performance, research activity and exposure fields are included. Unrecognized labeled columns are retained in `ExtraInfo` and displayed under **Other source fields**. Completely unlabeled columns are not imported; label any column that should appear in the tool.

Import without opening the GUI:

```matlab
[candidates, info] = HKPFS_load_candidates('Test_file_2025.xlsx');
```

For new header wording, extend the explicit aliases in `header_schema` inside `HKPFS_load_candidates.m`. Avoid broad substring matching that could confuse institution names with institution rankings or applicant names with supervisor names.

## Ranking method

The tool keeps manual 1–5 ratings and pairwise comparisons. It does not generate an automatic candidate score. A stable, iterative merge sort compares candidates only within the same rating, using at most O(n log n) comparisons. Indices are sorted before the candidate table is rearranged, avoiding repeated table growth and deletion. Pairwise preferences should be consistent; the tool does not resolve preference cycles.
