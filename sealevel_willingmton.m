% Wilmington, NC:
clear

T = daily_mean_from_hourly(1995, 2025, "wilmington_daily_mean.csv");
thr_value = 97; % threshold percentile for high sea level definition

t = T.date_gmt;
y = T.daily_mean_water_level_m;

% ---- trend fit (for detrending) ----
x = datenum(t);
ok = ~isnan(x) & ~isnan(y) & ~isnat(t);
p = polyfit(x(ok), y(ok), 1);  % p(1) % m/day

% --- detrend
y_detrend = y - polyval(p, x);

% --- remove seasonal cycle (monthly climatology)
m = month(t);
clim = accumarray(m(ok), y_detrend(ok), [12 1], @(z) mean(z,'omitnan'));
y_anom = y_detrend - clim(m);
seasonal   = clim(m);      % seasonal value for each day (same length as y)

% --- thresholds (raw and anomaly)
thr_raw  = prctile(y(ok), thr_value);
thr_anom = prctile(y_anom(ok), thr_value);

% --- exceedances
isFloodRaw   = ok & (y > thr_raw);
isStormEvent = ok & (y_anom > thr_anom);

% --- group exceedances into events (storm-based)
idx = find(isStormEvent);
events = table;

if ~isempty(idx)
    breaks  = [true; diff(idx) > 1];
    eventID = cumsum(breaks);

    startIdx = accumarray(eventID, idx, [], @min);
    endIdx   = accumarray(eventID, idx, [], @max);

    events.start_date    = t(startIdx);
    events.end_date      = t(endIdx);
    events.duration_days = days(events.end_date - events.start_date) + 1;
    events.peak_level_m  = accumarray(eventID, y(idx), [], @max); % peak RAW level during event
end

% ==============================
% NEW: annual counts (days) > thr_value percentile
% ==============================
yr = year(t);
yrs = (min(yr(ok)) : max(yr(ok)))';

% count days (not events) above thresholds for each year
nHigh_raw  = accumarray(yr(isFloodRaw)   - yrs(1) + 1, 1, [numel(yrs) 1], @sum, 0);
nHigh_anom = accumarray(yr(isStormEvent) - yrs(1) + 1, 1, [numel(yrs) 1], @sum, 0);

% --- plots 
figure(1)
plot(t, y, 'b'); hold on;
plot(t, y-y_detrend, 'LineWidth', 2);
plot(t,seasonal,'g', 'LineWidth', 2)
grid on;
xlabel('Date (GMT)');
ylabel('Daily mean water level (m)');
title(sprintf('Daily Mean Water Level, Seasonal cycle, Linear Trend (%.2f mm/yr)', p(1)*365.25*1000),'FontSize',14);
legend('Daily mean','seasonal cycle','Linear trend', 'Location','best');

figure(2)
plot(t, y_detrend-seasonal, 'b'); hold on;
grid on;
xlabel('Date (GMT)');
ylabel('Daily mean water level (m)');
title(sprintf('Daily Mean Water Level- Seasonal cycle - Linear Trend (%.2f mm/yr)', p(1)*365.25*1000),'FontSize',14);
legend('Daily mean anomaly', 'Location','best');


figure(3);
% decimal year = year + (day-of-year-1)/days-in-year
yr0 = year(t);
doy = day(t,'dayofyear');
daysInYr = day(datetime(yr0,12,31),'dayofyear');  % 365 or 366
tYear = yr0 + (doy-1)./daysInYr;                  % numeric x axis

% ----- common x settings -----
xmin = min(yrs) - 0.5;
xmax = max(yrs) + 0.5;

% choose tick spacing (5-year ticks usually good)
xt = (ceil(min(yrs)/5)*5 : 5 : floor(max(yrs)/5)*5)';

ax(1) = subplot(4,1,1);
plot(tYear(ok), y(ok), 'b'); hold on;
yline(thr_raw,'k--',sprintf('%dth percentile',thr_value));
plot(tYear(isFloodRaw), y(isFloodRaw), 'ro','MarkerFaceColor','r','MarkerSize',3);
%title(sprintf('Raw daily mean (impact-based, >%dth pct)', thr_value));
%title('Observed Daily Mean Sea Level and Extreme High-Water Days (Red dots, indicating days exceeding the 97th percentile of observed sea level')
title('Observed Sea Level and Extreme High-Water Days')
ylabel('Water level (m)');
grid on;

ax(2) = subplot(4,1,2);
bar(yrs, nHigh_raw);
%title(sprintf('Annual count of high sea level days (raw > %dth pct)', thr_value));
%title('Annual Frequency of High Sea Level Days (Impact-Based)')
title('Annual Frequency of High Sea Level Days')
ylabel('# days');
grid on;

ax(3) = subplot(4,1,3);
plot(tYear(ok), y_anom(ok), 'b'); hold on;
yline(thr_anom,'k--',sprintf('%dth percentile (anom)',thr_value));
plot(tYear(isStormEvent), y_anom(isStormEvent), 'ro','MarkerFaceColor','r','MarkerSize',3);
%title(sprintf('Detrended + deseasonalized (storm-based, >%dth pct)', thr_value));
%title('Storm-Driven Daily Mean Sea Level Anomalies (after removing long-term trend and seasonal clcyle) and Extreme High-Water Days (Red dots, indicating days exceeding the 97th percentile of sea level anomalies')
title('Storm-Driven Sea Level Anomalies and Extreme Events')
ylabel('Anomaly (m)');
grid on;

ax(4) = subplot(4,1,4);
bar(yrs, nHigh_anom);
%title(sprintf('Annual count of high sea level days (anom > %dth pct)', thr_value));
%title('Annual Frequency of Storm-Driven High Sea Level Events')
title('Annual Frequency of Storm-Driven High Sea Level Events')
ylabel('# days');
xlabel('Year');
grid on;

% ----- enforce SAME xlim + SAME xticks + SHOW year labels on every panel -----
for i = 1:4
    xlim(ax(i), [xmin xmax]);
    xticks(ax(i), xt);
    xticklabels(ax(i), string(xt));   % show year numbers on every panel
    ax(i).XGrid = 'on';
end

% ----- ensure identical left/right margins (alignment) -----
pos1 = ax(1).Position;
for i = 2:4
    pos = ax(i).Position;
    pos(1) = pos1(1);   % same left
    pos(3) = pos1(3);   % same width
    ax(i).Position = pos;
end

% Optional: make tick labels a bit smaller to avoid crowding
set(ax, 'TickDir','out', 'Box','on');
set(ax, 'FontSize', 10);

% Optional: label x-axis on panels 1-3 too (if you want)
%xlabel(ax(1),'Year');
%xlabel(ax(2),'Year');
%xlabel(ax(3),'Year');