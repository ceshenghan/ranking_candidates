function FinalSortedList = HKPFS_GUI_Tool_Optimized(filename, outputFilename, varargin)
%HKPFS_GUI_TOOL_OPTIMIZED Review, rate, compare and export HKPFS candidates.
% Run HKPFS_GUI_Tool_Optimized to open the bundled synthetic workbook.
% T = HKPFS_GUI_Tool_Optimized(inputFile, outputFile, 'Sheet', 'Applicants')
% Optional loader arguments: 'Sheet' and 'HeaderRow'. Requires MATLAB R2020b+.
% Keep HKPFS_load_candidates, HKPFS_rank_candidates and HKPFS_export_ranking
% alongside this file.
% Ratings are assigned by the reviewer; source research scores are not ratings.
    FinalSortedList = table();
    if nargin < 1 || strlength(string(filename)) == 0
        filename = fullfile(fileparts(mfilename('fullpath')), 'Test_file_2025.xlsx');
        if ~isfile(filename)
            [f,p] = uigetfile({'*.xlsx;*.xls','Excel workbooks'}, 'Select candidate workbook');
            if isequal(f,0), return; end
            filename = fullfile(p,f);
        end
    end
    if nargin < 2, outputFilename = ''; end
    try
        try
            [Candidates, info] = HKPFS_load_candidates(filename, varargin{:});
        catch ME
            if ~strcmp(ME.identifier,'HKPFS:AmbiguousSheet'), rethrow(ME); end
            sheets = string(sheetnames(filename));
            [idx,ok] = listdlg('ListString',cellstr(sheets),'SelectionMode','single', ...
                'PromptString','Select the worksheet containing candidates:');
            if ~ok, return; end
            [Candidates, info] = HKPFS_load_candidates(filename, varargin{:}, 'Sheet',sheets(idx));
        end
        fprintf('Loaded %d candidates: sheet "%s", header row %d.\n', ...
            height(Candidates),info.Sheet,info.HeaderRow);
        if ~isempty(info.MissingFields)
            fprintf('Optional fields not supplied: %s\n',strjoin(info.MissingFields,', '));
        end
        [Candidates, completed] = run_rating_gui(Candidates, info);
        if ~completed
            fprintf('Review cancelled. No final ranking was exported.\n');
            return;
        end
        [compare, cleanup] = comparison_window(); %#ok<ASGLU>
        [ranked, count] = HKPFS_rank_candidates(Candidates, compare);
        clear cleanup;
        % Keep the complete ranked result available even if Save As is cancelled.
        FinalSortedList = ranked;
        if strlength(string(outputFilename)) == 0
            [f,p] = uiputfile('*.xlsx','Save final ranking', ...
                fullfile(fileparts(char(filename)),'Final_HKPFS_Ranking.xlsx'));
            if isequal(f,0)
                fprintf('Ranking complete; export cancelled. The returned table contains the results.\n');
                return;
            end
            outputFilename = fullfile(p,f);
        end
        HKPFS_export_ranking(ranked, outputFilename, filename);
        fprintf('Saved %d candidates after %d comparisons to %s\n',height(ranked),count,outputFilename);
        msgbox(sprintf('Ranked %d candidates.\nSaved to %s',height(ranked),outputFilename),'Ranking complete');
    catch ME
        if strcmp(ME.identifier,'HKPFS:Cancelled')
            fprintf('%s\n',ME.message);
        else
            if nargout > 0, rethrow(ME); end
            errordlg(ME.message,'HKPFS tool');
        end
    end
end

function [Candidates, completed] = run_rating_gui(Candidates, info)
    n = height(Candidates); current = 1; completed = false;
    baseline = Candidates;
    fig = uifigure('Name','HKPFS candidate review','Position',[100 80 980 820], ...
        'CloseRequestFcn',@(~,~) cancel_review());
    cleanup = onCleanup(@() close_figure(fig));
    g = uigridlayout(fig,[7 1]);
    g.RowHeight = {28,40,'1x',24,85,54,40};
    progress = uilabel(g,'FontWeight','bold');
    name = uilabel(g,'FontSize',18,'FontWeight','bold');
    details = uitextarea(g,'Editable','off','FontSize',13);
    uilabel(g,'Text','Reviewer notes (saved with the ranking):');
    notes = uitextarea(g,'FontSize',12);
    ratingGrid = uigridlayout(g,[1 6]);
    ratingGrid.ColumnWidth = {170,'1x','1x','1x','1x','1x'};
    rateLabel = uilabel(ratingGrid);
    rateButtons = gobjects(1,5);
    for k = 1:5
        rateButtons(k) = uibutton(ratingGrid,'Text',sprintf('%d',k),'FontSize',18, ...
            'ButtonPushedFcn',@(~,~) set_rate(k));
    end
    nav = uigridlayout(g,[1 5]);
    previous = uibutton(nav,'Text','Previous','ButtonPushedFcn',@(~,~) navigate(-1));
    next = uibutton(nav,'Text','Next','ButtonPushedFcn',@(~,~) navigate(1));
    uibutton(nav,'Text','Load progress','ButtonPushedFcn',@(~,~) load_progress());
    uibutton(nav,'Text','Save progress','ButtonPushedFcn',@(~,~) save_progress());
    finish = uibutton(nav,'Text','Start ranking','ButtonPushedFcn',@(~,~) finish_review());
    update_display();
    uiwait(fig);

    function store_notes()
        Candidates.ReviewerNotes(current) = strjoin(string(notes.Value),newline);
    end
    function update_display()
        progress.Text = sprintf('%d / %d reviewed | Candidate %d / %d | %s, Excel row %d (header %d)', ...
            nnz(Candidates.Rate),n,current,n,info.Sheet,Candidates.SourceRow(current),info.HeaderRow);
        name.Text = sprintf('%s | HKPFS: %s | Application: %s', ...
            Candidates.Name(current),Candidates.HKPFS_No(current),Candidates.AppNo(current));
        details.Value = splitlines(candidate_text(Candidates(current,:)));
        notes.Value = splitlines(Candidates.ReviewerNotes(current));
        if Candidates.Rate(current) == 0
            rateLabel.Text = 'Rating: not assigned';
        else
            rateLabel.Text = sprintf('Current rating: %d / 5',Candidates.Rate(current));
        end
        for j = 1:5
            rateButtons(j).BackgroundColor = [0.94 0.94 0.94];
            if Candidates.Rate(current) == j, rateButtons(j).BackgroundColor = [0.66 0.84 0.98]; end
        end
        previous.Enable = onoff(current > 1);
        next.Enable = onoff(current < n);
        finish.Enable = onoff(all(Candidates.Rate >= 1 & Candidates.Rate <= 5));
    end
    function set_rate(value)
        store_notes(); Candidates.Rate(current) = value;
        current = min(current+1,n);
        update_display();
    end
    function navigate(step)
        store_notes(); current = max(1,min(n,current+step)); update_display();
    end
    function finish_review()
        store_notes();
        if any(Candidates.Rate == 0), return; end
        completed = true; uiresume(fig);
    end
    function cancel_review()
        completed = false; uiresume(fig); delete(fig);
    end
    function save_progress()
        store_notes();
        [f,p] = uiputfile('*.mat','Save review progress','HKPFS_Review_Progress.mat');
        if isequal(f,0), return; end
        progressData = struct('Version',1,'Candidates',Candidates);
        try
            save(fullfile(p,f),'progressData');
        catch ME
            uialert(fig,ME.message,'Could not save progress');
        end
    end
    function load_progress()
        [f,p] = uigetfile('*.mat','Load review progress');
        if isequal(f,0), return; end
        try
            saved = load(fullfile(p,f),'progressData');
            if ~isfield(saved,'progressData') || saved.progressData.Version ~= 1
                error('HKPFS:InvalidProgress','This is not a supported review progress file.');
            end
            restored = saved.progressData.Candidates;
            cols = setdiff(baseline.Properties.VariableNames,{'Rate','ReviewerNotes'},'stable');
            if ~istable(restored) || ~isequaln(restored(:,cols),baseline(:,cols)) || ...
                    ~isnumeric(restored.Rate) || ~isequal(size(restored.Rate),[n,1]) || ...
                    any(~isfinite(restored.Rate) | restored.Rate < 0 | restored.Rate > 5 | fix(restored.Rate) ~= restored.Rate) || ...
                    ~isstring(restored.ReviewerNotes) || ~isequal(size(restored.ReviewerNotes),[n,1])
                error('HKPFS:ProgressMismatch','Progress does not match this workbook, row order or candidate data.');
            end
            Candidates.Rate = restored.Rate;
            Candidates.ReviewerNotes = restored.ReviewerNotes;
            current = find(Candidates.Rate == 0,1);
            if isempty(current), current = 1; end
            update_display();
        catch ME
            uialert(fig,ME.message,'Could not load progress');
        end
    end
end

function [compare, cleanup] = comparison_window()
    fig = uifigure('Name','HKPFS pairwise ranking','Position',[80 80 1200 800], ...
        'CloseRequestFcn',@(~,~) cancel());
    cleanup = onCleanup(@() close_figure(fig));
    grid = uigridlayout(fig,[5 2]);
    grid.RowHeight = {32,50,'1x',48,26};
    heading = uilabel(grid,'FontSize',16,'FontWeight','bold');
    heading.Layout.Column = [1 2];
    names = gobjects(1,2); texts = gobjects(1,2);
    for k = 1:2
        names(k) = uilabel(grid,'FontSize',14,'FontWeight','bold','WordWrap','on');
    end
    for k = 1:2
        texts(k) = uitextarea(grid,'Editable','off','FontSize',13);
    end
    uibutton(grid,'Text','Rank A higher','ButtonPushedFcn',@(~,~) select(1));
    uibutton(grid,'Text','Rank B higher','ButtonPushedFcn',@(~,~) select(2));
    helpLabel = uilabel(grid,'Text','For equal preference, choose A to preserve source order. Close this window to cancel ranking.');
    helpLabel.Layout.Column = [1 2];
    choice = 0;
    compare = @ask;
    function result = ask(a,b,rate,count)
        if ~isgraphics(fig), result = 0; return; end
        choice = 0;
        heading.Text = sprintf('Rating %d / 5 | Comparison %d | Which candidate should rank higher?',rate,count);
        names(1).Text = sprintf('A: %s (HKPFS %s)',a.Name,a.HKPFS_No);
        names(2).Text = sprintf('B: %s (HKPFS %s)',b.Name,b.HKPFS_No);
        texts(1).Value = splitlines(candidate_text(a));
        texts(2).Value = splitlines(candidate_text(b));
        uiwait(fig);
        result = choice;
    end
    function select(value)
        choice = value; uiresume(fig);
    end
    function cancel()
        choice = 0; uiresume(fig); delete(fig);
    end
end

function txt = candidate_text(row)
    fields = {'Sequence','AppNo','Pool','DepartmentRank','Program','Origin','Gender', ...
        'UG','UGRank','UGDegree','PG','PGRank','PGDegree','English','Awards', ...
        'Research','Pubs','ResearchPotential','Exposure','AddInfo','ExtraInfo','ReviewerNotes'};
    labels = {'SEQUENCE','APPLICATION NUMBER','POOL','SCHOOL / DEPARTMENT RANK','PROGRAM', ...
        'PLACE OF ORIGIN','GENDER','UG INSTITUTION','UG RANK / REPUTATION','UG DEGREE & PERFORMANCE', ...
        'PG INSTITUTION','PG RANK / REPUTATION','PG DEGREE & PERFORMANCE','ENGLISH PROFICIENCY', ...
        'AWARDS','RESEARCH EXPERIENCE','PUBLICATIONS','SOURCE RESEARCH ABILITY & POTENTIAL', ...
        'INTERNATIONAL / INTERCULTURAL EXPOSURE','ADDITIONAL INFORMATION','OTHER SOURCE FIELDS','REVIEWER NOTES'};
    parts = strings(numel(fields),1);
    for k = 1:numel(fields)
        value = row.(fields{k});
        if ismissing(value) || strlength(value) == 0, value = "Not supplied"; end
        parts(k) = string(labels{k}) + newline + value;
    end
    txt = strjoin(parts,sprintf('\n\n'));
end

function value = onoff(condition)
    if condition, value = 'on'; else, value = 'off'; end
end

function close_figure(fig)
    if isgraphics(fig), delete(fig); end
end
