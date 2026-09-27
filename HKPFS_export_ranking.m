function HKPFS_export_ranking(ranked, filename, sourceFilename)
%HKPFS_EXPORT_RANKING Write summary and full profiles without stale rows.
% Stage both sheets in the destination directory before replacing the target.
    if nargin < 3, sourceFilename = ''; end
    filename = char(filename);
    [folder,~,ext] = fileparts(filename);
    if ~strcmpi(ext,'.xlsx'), error('HKPFS:OutputFormat','Choose an .xlsx output filename.'); end
    if isempty(folder), folder = pwd; end
    if ~isfolder(folder), error('HKPFS:OutputFolder','Output folder does not exist: %s',folder); end
    target = char(java.io.File(filename).getCanonicalPath());
    if ~isempty(sourceFilename) && strcmpi(target,char(java.io.File(char(sourceFilename)).getCanonicalPath()))
        error('HKPFS:SourceOverwrite','Choose an output filename different from the source workbook.');
    end
    required = {'Ranking','Sequence','Rate','Name','HKPFS_No','AppNo','ReviewerNotes','SourceSheet','SourceRow'};
    if ~istable(ranked) || ~all(ismember(required,ranked.Properties.VariableNames)) || isempty(ranked)
        error('HKPFS:InvalidExport','The ranking is empty or missing required fields.');
    end
    rates = ranked.Rate;
    if any(~isfinite(rates) | rates < 1 | rates > 5 | fix(rates) ~= rates) || ...
            any(diff(rates) > 0) || ~isequal(ranked.Ranking,(1:height(ranked))')
        error('HKPFS:InvalidExport','Only a complete, ordered ranking can be exported.');
    end
    temp = [tempname(folder),'.xlsx'];
    cleanup = onCleanup(@() remove_temp(temp));
    summary = ranked(:,required);
    summary.Properties.VariableNames{strcmp(summary.Properties.VariableNames,'HKPFS_No')} = 'HKPFS_no';
    writetable(summary,temp,'Sheet','Ranking');
    writetable(ranked,temp,'Sheet','Candidate details');
    [ok,message] = movefile(temp,filename,'f');
    if ~ok, error('HKPFS:ExportFailed','Could not save the ranking: %s',message); end
end

function remove_temp(filename)
    if isfile(filename), delete(filename); end
end
