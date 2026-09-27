function [ranked, comparisonCount] = HKPFS_rank_candidates(candidates, compare)
%HKPFS_RANK_CANDIDATES Rank 5-to-1, using merge sort inside each rating.
% COMPARE(A,B,RATE,NUMBER) must return 1 (A first), 2 (B first), or
% 0 (cancel). The comparator is called only for equally rated candidates.
% A deterministic, transitive preference yields O(n log n) comparisons.
% Choosing A for equal preferences preserves source order (stable sort).
    if ~istable(candidates) || ~ismember('Rate', candidates.Properties.VariableNames)
        error('HKPFS:InvalidCandidates', 'Expected a candidate table with a Rate column.');
    end
    rates = candidates.Rate;
    if ~isnumeric(rates) || size(rates,2) ~= 1 || any(~isfinite(rates) | rates < 1 | rates > 5 | fix(rates) ~= rates)
        error('HKPFS:IncompleteRatings', 'Every candidate must have an integer rating from 1 to 5.');
    end
    if ~isa(compare,'function_handle'), error('HKPFS:InvalidComparator', 'Provide a comparison function.'); end
    comparisonCount = 0;
    order = zeros(height(candidates),1);
    cursor = 1;
    for rate = 5:-1:1
        idx = find(rates == rate);
        n = numel(idx);
        width = 1;
        while width < n
            next = idx;
            for start = 1:2*width:n
                mid = min(start+width-1,n); stop = min(start+2*width-1,n);
                a = start; b = mid+1; dest = start;
                while a <= mid && b <= stop
                    comparisonCount = comparisonCount+1;
                    choice = compare(candidates(idx(a),:), candidates(idx(b),:), rate, comparisonCount);
                    if ~isnumeric(choice) || ~isscalar(choice) || ~ismember(choice,[0 1 2])
                        error('HKPFS:InvalidChoice', 'Comparison must return 0, 1 or 2.');
                    end
                    if choice == 0, error('HKPFS:Cancelled', 'Ranking cancelled. No final ranking was exported.'); end
                    if choice == 1
                        next(dest) = idx(a); a = a+1;
                    else
                        next(dest) = idx(b); b = b+1;
                    end
                    dest = dest+1;
                end
                rest = [idx(a:mid); idx(b:stop)];
                next(dest:stop) = rest;
            end
            idx = next; width = width*2;
        end
        order(cursor:cursor+n-1) = idx;
        cursor = cursor+n;
    end
    ranked = candidates(order,:);
    ranked.Ranking = (1:height(ranked))';
    ranked = movevars(ranked,'Ranking','Before',1);
end
