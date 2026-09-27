function [Candidates, info] = HKPFS_load_candidates(filename, varargin)
%HKPFS_LOAD_CANDIDATES Import a candidate table independently of its position.
% [T, INFO] = HKPFS_load_candidates(FILE, 'Sheet', 'Applicants')
% [T, INFO] = HKPFS_load_candidates(FILE, 'HeaderRow', 10)
% Requires Name and at least one of HKPFS number / Application number.
% Header aliases ignore case, whitespace, line breaks and punctuation.
% Extra columns are retained as text in ExtraInfo. No scores are inferred.
    p = inputParser;
    addRequired(p, 'filename', @(x) ischar(x) || (isstring(x) && isscalar(x)));
    addParameter(p, 'Sheet', "", @(x) ischar(x) || (isstring(x) && isscalar(x)) || ...
        (isnumeric(x) && isscalar(x) && isfinite(x) && x >= 1 && fix(x) == x));
    addParameter(p, 'HeaderRow', [], @(x) isempty(x) || ...
        (isnumeric(x) && isscalar(x) && isfinite(x) && x >= 1 && fix(x) == x));
    parse(p, filename, varargin{:});
    if ~isfile(filename)
        error('HKPFS:FileNotFound', 'Workbook not found: %s', filename);
    end
    sheets = string(sheetnames(filename));
    selected = p.Results.Sheet;
    if isnumeric(selected)
        if selected > numel(sheets), error('HKPFS:SheetNotFound', 'Sheet index is out of range.'); end
        sheets = sheets(selected);
    elseif strlength(string(selected)) > 0
        if ~any(sheets == string(selected))
            error('HKPFS:SheetNotFound', 'Worksheet not found: %s', selected);
        end
        sheets = string(selected);
    end
    [fields, patterns] = header_schema();
    found = struct('Sheet', {}, 'Row', {}, 'Map', {}, 'Text', {});
    for s = 1:numel(sheets)
        % Anchoring at A1 preserves physical Excel row/column coordinates.
        raw = readcell(filename, 'Sheet', sheets(s), 'Range', 'A1');
        cells = cell_text(raw);
        bestScore = 0; bestRow = 0; bestMap = [];
        rows = 1:size(cells, 1);
        if ~isempty(p.Results.HeaderRow), rows = p.Results.HeaderRow; end
        for r = rows
            if r > size(cells, 1), continue; end
            map = map_headers(cells(r,:), patterns);
            if is_header(map)
                score = nnz(map);
                if score > bestScore
                    bestScore = score; bestRow = r; bestMap = map;
                end
            end
        end
        if bestRow > 0
            found(end+1) = struct('Sheet', sheets(s), 'Row', bestRow, ...
                'Map', bestMap, 'Text', cells); %#ok<AGROW>
        end
    end
    if isempty(found)
        error('HKPFS:HeaderNotFound', ['No candidate header found. A single header row must contain ' ...
            'Name and HKPFS no. or Application no. (in any columns).']);
    elseif numel(found) > 1
        error('HKPFS:AmbiguousSheet', 'Candidate tables found on multiple sheets: %s. Specify ''Sheet''.', ...
            strjoin([found.Sheet], ', '));
    end
    src = found(1); map = src.Map;
    headers = src.Text(src.Row,:);
    % Detect ambiguous aliases instead of silently choosing a column.
    for f = 1:numel(fields)
        matches = header_matches(headers, patterns{f});
        if nnz(matches) > 1
            error('HKPFS:DuplicateHeader', 'Multiple columns match %s on sheet %s, row %d.', ...
                fields{f}, src.Sheet, src.Row);
        end
    end
    data = src.Text(src.Row+1:end,:);
    sourceRows = (src.Row+1:size(src.Text,1))';
    repeated = false(size(data,1),1);
    for r = 1:size(data,1)
        % Most data rows cannot be headers; avoid normalizing every profile.
        nameToken = normalize_header(data(r,map(2)));
        if ~any(nameToken == ["name","candidatename","applicantname","fullname"]), continue; end
        rowMap = map_headers(data(r,:), patterns);
        if is_header(rowMap)
            if ~isequal(rowMap, map)
                error('HKPFS:ChangedHeader', 'A different column layout starts at Excel row %d. Split it into a separate sheet.', sourceRows(r));
            end
            repeated(r) = true;
        end
    end
    Candidates = table();
    for f = 1:numel(fields)
        values = strings(size(data,1),1);
        if map(f) > 0, values = data(:,map(f)); end
        Candidates.(fields{f}) = values;
    end
    namePresent = Candidates.Name ~= "";
    idPresent = Candidates.HKPFS_No ~= "" | Candidates.AppNo ~= "";
    keep = (namePresent | idPresent | Candidates.Sequence ~= "") & ~repeated;
    invalid = keep & ~(namePresent & idPresent);
    if any(invalid)
        error('HKPFS:IncompleteCandidate', ['Incomplete candidate identity at Excel row(s) %s. ' ...
            'Each candidate needs a name and at least one application/HKPFS identifier.'], ...
            strjoin(string(sourceRows(invalid)), ', '));
    end
    if ~any(keep), error('HKPFS:NoCandidates', 'The detected table has no candidate records.'); end
    Candidates = Candidates(keep,:);
    Candidates.SourceSheet = repmat(src.Sheet, height(Candidates), 1);
    Candidates.SourceRow = sourceRows(keep);
    generated = Candidates.Sequence == "";
    Candidates.Sequence(generated) = "row-" + string(Candidates.SourceRow(generated));
    for field = { 'HKPFS_No', 'AppNo' }
        values = lower(strtrim(Candidates.(field{1})));
        values = values(values ~= "");
        if numel(unique(values)) ~= numel(values)
            error('HKPFS:DuplicateID', 'Duplicate %s values found on sheet %s. Correct them before ranking.', field{1}, src.Sheet);
        end
    end
    extraColumns = setdiff(find(headers ~= ""), map(map > 0));
    extra = strings(height(Candidates),1);
    keptData = data(keep,:);
    for c = extraColumns
        for r = 1:height(Candidates)
            if keptData(r,c) ~= ""
                extra(r) = extra(r) + headers(c) + ": " + keptData(r,c) + newline + newline;
            end
        end
    end
    Candidates.ExtraInfo = strtrim(extra);
    Candidates.Rate = zeros(height(Candidates),1);
    Candidates.ReviewerNotes = strings(height(Candidates),1);
    info = struct('Sheet',src.Sheet, 'HeaderRow',src.Row, ...
        'CandidateCount',height(Candidates), 'SkippedRows',sourceRows(~keep), ...
        'GeneratedSequenceRows',Candidates.SourceRow(generated), ...
        'MissingFields',{fields(map == 0)}, 'ColumnMap',map, 'Fields',{fields});
end

function tf = is_header(map)
    tf = map(2) > 0 && (map(3) > 0 || map(4) > 0);
end

function map = map_headers(headers, patterns)
    normalized = normalize_header(headers);
    map = zeros(1,numel(patterns));
    for f = 1:numel(patterns)
        idx = find(~cellfun('isempty', regexp(cellstr(normalized), patterns{f}, 'once')),1);
        if ~isempty(idx), map(f) = idx; end
    end
end

function matches = header_matches(headers, pattern)
    matches = ~cellfun('isempty', regexp(cellstr(normalize_header(headers)), pattern, 'once'));
end

function s = normalize_header(s)
    s = regexprep(lower(s), '[^a-z0-9]', '');
end

function out = cell_text(raw)
    out = strings(size(raw));
    for k = 1:numel(raw)
        val = raw{k};
        if isempty(val) || (isscalar(val) && ismissing(val)), continue; end
        out(k) = strtrim(string(val));
    end
end

function [fields, patterns] = header_schema()
    % Specific anchored aliases prevent Name matching Supervisor Name, and
    % UG Institution matching UG Institution Ranking/Reputation.
    fields = {'Sequence','Name','HKPFS_No','AppNo','Origin','UG','UGRank', ...
        'PG','PGRank','English','Awards','Pubs','AddInfo','UGDegree','PGDegree', ...
        'Research','ResearchPotential','Exposure','Pool','DepartmentRank','Program','Gender'};
    patterns = {
        '^(sequence|seq|sequenceno|sequencenumber|serialno|serialnumber)$'
        '^(name|candidatename|applicantname|fullname)$'
        '^(hkpfs|hkpfsno|hkpfsnumber|hkpfsid|hkpfsapplicationno|hkpfsapplicationnumber)$'
        '^(applicationno|applicationnumber|applicationid|appno|appnumber|appid)$'
        '^(placeoforigin|origin|countryoforigin)$'
        '^(uginstitution|undergraduateinstitution|uguniversity|undergraduateuniversity)$'
        '^(uginstitutionranking|uginstitutionreputation|ugrank|undergraduateinstitutionranking)'
        '^(pginstitution|postgraduateinstitution|pguniversity|postgraduateuniversity)$'
        '^(pginstitutionranking|pginstitutionreputation|pgrank|postgraduateinstitutionranking)'
        '^(englishproficiency|englishlanguageproficiency|englishscore|english)$|^englishproficiency'
        '^(academicresearchrelatedawards|academicawards|researchawards|awards)'
        '^(publications?|papers)(papers|ifany|published|accepted|underreview|submitted|$)'
        '^(additionalinformation|additionalinfo|addinfo|remarks)'
        '^(ugdegree|undergraduatedegree|ugperformance)'
        '^(pgdegree|postgraduatedegree|pgperformance)'
        '^(involvementinresearch|researchactivities|researchexperience)'
        '^(researchabilitypotential|researchpotential)'
        '^(internationalinterculturalexposure|internationalexposure|interculturalexposure)'
        '^(guaranteedreservedpool|guaranteedpoolreservedpool|pool|nominationpool)$'
        '^(schooldeptranking|schooldepartmentranking|departmentranking)$'
        '^(phdprogram|phdprogramme|program|programme)$'
        '^(gender|sex)$'};
end
