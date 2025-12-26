function Tdaily = daily_mean_from_hourly(beginYear, endYear, outCsv)
%WILMINGTON_DAILY_MEAN_FROM_HOURLY
% Download NOAA CO-OPS verified hourly water level (hourly_height) for
% Wilmington, NC (station 8658120), then compute daily means.
%
% Key robustness upgrades:
%  - Caps the final request end_date to today (avoids future-date 400 errors)
%  - Requires a minimum number of hourly samples per day (default 18) or returns NaN
%  - Uses GMT timezone consistently
%  - Safer handling of missing/empty value strings

    if nargin < 1 || isempty(beginYear), beginYear = 1995; end
    if nargin < 2 || isempty(endYear),   endYear   = year(datetime('today')); end
    if nargin < 3 || isempty(outCsv),    outCsv    = "wilmington_daily_mean.csv"; end

    % ---- User-tunable settings ----
    station  = "8658120";   % Wilmington, NC
    datum    = "MSL";       % Consider "NAVD" or "STND" depending on your use case
    units    = "metric";    % "english" for feet
    tz       = "gmt";       % NOAA API expects: gmt, lst, lst_ldt
    minHours = 18;          % minimum hourly samples required for a daily mean

    base = "https://api.tidesandcurrents.noaa.gov/api/prod/datagetter";

    % Accumulate yearly timetables in a cell array (faster than repeated concatenation)
    years = beginYear:endYear;
    TTcell = cell(numel(years), 1);

    % Today's date for capping the last year's request
    today = datetime('today','TimeZone','GMT');
    todayStr = datestr(today, 'yyyymmdd');
    thisYear = year(today);

    for k = 1:numel(years)
        yy = years(k);

        begin_date = sprintf("%04d0101", yy);

        % Cap end date if requesting the current year or a future year
        if yy > thisYear
            warning("Year %d is in the future relative to today; skipping.", yy);
            continue;
        elseif yy == thisYear
            end_date = todayStr;
        else
            end_date = sprintf("%04d1231", yy);
        end

        params = [
            "product=hourly_height"
            "application=matlab_noaa_coops"
            "begin_date=" + begin_date
            "end_date="   + end_date
            "station="    + station
            "datum="      + datum
            "units="      + units
            "time_zone="  + tz
            "format=json"
        ];

        url = base + "?" + strjoin(params, "&");
        url

        opts = weboptions("Timeout", 60);
        resp = webread(url, opts);

        if isfield(resp, "error")
            error("NOAA API error for %d: %s", yy, resp.error.message);
        end
        if ~isfield(resp, "data") || isempty(resp.data)
            warning("No data returned for year %d (URL: %s)", yy, url);
            continue;
        end

        D = resp.data;

        % Expected fields:
        %  t: 'YYYY-MM-DD HH:MM'
        %  v: value string (meters or feet depending on units)
        t = string({D.t})';
        v = string({D.v})';

        % Parse datetime in GMT
        dt = datetime(t, "InputFormat","yyyy-MM-dd HH:mm", "TimeZone","GMT");

        % Convert values to double; handle missing/blank values safely
        v = strtrim(v);
        v(v == "" | lower(v) == "nan") = missing;
        wl = str2double(v);

        TTcell{k} = timetable(dt, wl, 'VariableNames', {'water_level'});
    end

    % Concatenate all years (dropping empties)
    TTcell = TTcell(~cellfun(@isempty, TTcell));
    if isempty(TTcell)
        error("No data downloaded. Check station/datum or internet connectivity.");
    end
    allTT = vertcat(TTcell{:});

    % Ensure sorted unique timestamps
    allTT = sortrows(allTT);
    allTT = unique(allTT);

    % Daily mean with minimum-hour requirement
    dailyFun = @(x) (sum(~isnan(x)) >= minHours) .* mean(x,'omitnan');

    %dailyFun = @(x) (sum(~isnan(x)) >= minHours) .* mean(x,'omitnan') + (sum(~isnan(x)) <  minHours) .* NaN;

    dailyTT = retime(allTT, "daily", dailyFun);

    % Clean output table
    dailyTT.Properties.VariableNames = {'daily_mean_water_level'};
    Tdaily = table( ...
        datetime(dailyTT.dt, 'TimeZone','GMT'), ...
        dailyTT.daily_mean_water_level, ...
        'VariableNames', {'date_gmt','daily_mean_water_level_m'} );

    % Add simple metadata
    Tdaily.Properties.Description = "Daily mean water level from NOAA CO-OPS station 8658120 (Wilmington, NC) computed from hourly_height.";
    Tdaily.Properties.UserData.station = station;
    Tdaily.Properties.UserData.datum   = datum;
    Tdaily.Properties.UserData.units   = units;
    Tdaily.Properties.UserData.time_zone = tz;
    Tdaily.Properties.UserData.minHoursPerDay = minHours;

    % Save
    writetable(Tdaily, outCsv);
    fprintf("Saved %d daily rows to %s\n", height(Tdaily), outCsv);
end
