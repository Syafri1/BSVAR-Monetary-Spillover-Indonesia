% This script replicates the results in:
% Jarocinski, Karadi, Deconstructing Monetary Policy Surprises - The Role 
% of Information Shocks, forthcoming in the AEJ:Macroeconomics.
%
% The script estimates a monthly VAR with high-frequency monetary policy
% surprises and identifies shocks with sign restrictions.
% The different results in the paper can be obtained by uncommenting the
% appropriate lines.
clc
clear all, close all

% SAMPLE AND DATA: spl, modname, addvar
spl = [2005 8; 2025 3]
%spl = [1984 2; 2016 12];% ori
%spl = [1984 2; 2008 12];% Dec2008 ZLB reached
%spl = [1990 2; 2016 12];% Feb1999 surprises start
%spl = [1979 7; 2016 12];% GertlerKaradi2015 sample 

modname = 'indo'; %'us1','us1','ea1','us2','ea2'
addvar = ''; %'exp_gdp_12m','exp_cpi_12m','bkeven05','gs10','sven5f5'

% IDENTIFICATION: idscheme, mnames
idscheme = 'sgnm2'; %''chol','sgnm2strg','supdem'

mnames = {'ff4_hf','sp500_hf'}; % US baseline
%mnames = {'ff4_hf'};
%mnames = {'pmnegm_ff4sp500','pmposm_ff4sp500'}; % poor man's sign restrictions
%mnames = {'ff4_hf','sp500_hf','dbkeven02_d'}; % for supdem identification
%mnames = {'pc1ff1_hf','usstocks1_hf'}; % VAR with factors (Online Appendix C.4)
%mnames = {'pmnegm_pc1ff1usstocks1','pmposm_pc1ff1usstocks1'}; % VAR with factors, poor man's shocks (Online Appendix C.4)

%mnames = {'eureon3m_hf','stoxx50_hf'}; % euro area baseline
%mnames = {'eureon3m_hf'};
%mnames = {'pmnegm_eureon3mstoxx50','pmposm_eureon3mstoxx50'}; % poor man's sign restrictions
%mnames = {'eureon3m_hf','stoxx50_hf','deurinflswap2y_d'}; % for supdem identification

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% PRIOR
prior.lags = 12;
prior.minnesota.tightness = .1;
prior.minnesota.decay = 1;
prior.Nm = length(mnames);

% create the output folder based on the calling filename
st = dbstack; pathout = st(end).name; clear st 
mkdir(pathout)
pathout = [pathout '/'];

% functions for time operations
ym2t = @(x) x(1)+x(2)/12 - 1/24; % convert [year month] into time
t2datestr = @(t) [num2str(floor(t)) char(repmat(109,length(t),1)) num2str(12*(t-floor(t)+1/24),'%02.0f')];
t2ym = @(t) [floor(t) round(12*(t-floor(t)+1/24))]; % convert time into [year month]
ymdif = @(x1,x2) (x2(1)-x1(1))*12+x2(2)-x1(2);
findym = @(x,t) find(abs(t-ym2t(x))<1e-6); % find [year month] in time vector t

% Gibbs sampler settings
gssettings.ndraws = 4000;
gssettings.burnin = 4000;
gssettings.saveevery = 4;
gssettings.computemarglik = 0;

% detect poorman shocks and if yes override the identification to choleski
if (~isempty(strfind(mnames{1},'neg')) && ~isempty(strfind(mnames{2},'pos')))
    idscheme = 'chol';
end

% nice names
mdict = {'ff4_',    'Surprise in\newlineFederal Fund Futures';
         'sp500_',  'Surprise in\newlineS&P500'};
%{'eureon3m_', '  surprise in\newline3m Eonia swaps';
%    'stoxx50_', 'surprise in\newline Euro Stoxx 50';
%    'ff4_', '  surprise in\newline3m ff futures';
%    'sp500_', 'surprise in\newlineS&P500';
%    'pc1ff1_', 'surprise in\newlinepolicy ind.';
%    'usstocks1_', 'surprise in\newline1pc of stocks'};
mnames_nice = applydictregexp(mnames, mdict);
mylimits = nan(length(mnames),2);

% define y
ny1 = 5;
switch modname
    case 'indo'
        ynames = {'BIRate','1ybond','LnIHSG','LnIPI','LnIHK'};
        %ynames = {'1ybond','LnIHSG','LnIPI','LnIHK','BIRate'};
    case 'us1'
        ynames = {'gs1','logsp500','us_rgdp','us_gdpdef','ebpnew'};
    case 'us2'
        ynames = {'gs1','logsp500','us_ip','us_cpi','ebpnew'};
    case 'ea1'
        ynames = {'de1y_haver','stoxx50','ea_rgdp','ea_gdpdef','ea_bbb_oas_all_fred'};
    case 'ea2'
        ynames = {'de1y_haver','stoxx50','ea_ip_excl_constr','hicp','ea_bbb_oas_all_fred'};
    otherwise
        disp(modname), error('unknown modname');
end

if ~isempty(addvar)
    try
        findstrings(addvar,ynames);
    catch
        ynames = [ynames {addvar}]; modname = [modname '_' addvar];
    end
end

% nice_names, yylimits, nonst
dictfname = 'C:/Users/lenovo/Documents/SKRIPSI/SKRIPSI 2.0/Jarocinski & Karadi, 2020_packages yang digunakan/data/data_var/indodict_fix.csv';
fileID = fopen(dictfname);
ydict = textscan(fileID,'%s %q %d %f %f','Delimiter',',','HeaderLines',1);
fclose(fileID);
ynames_nice = applydict(ynames, [ydict{1} ydict{2}]);%ynames_nice = ynames;
yylimits = [ydict{4} ydict{5}];
yylimits = yylimits(findstrings(ynames,ydict{1}),:);
nonst = ydict{3};
nonst = nonst(findstrings(ynames,ydict{1}),:);

% load data
datafname = 'C:/Users/lenovo/Documents/SKRIPSI/SKRIPSI 2.0/Jarocinski & Karadi, 2020_packages yang digunakan/data/data_var/data_final_fix.csv';
data.Nm = length(mnames);
data.names = [mnames ynames];
d = importdata(datafname); dat = d.data; txt = d.colheaders;
tbeg = find(dat(:,1)==spl(1,1) & dat(:,2)==spl(1,2)); if isempty(tbeg), tbeg=1; end
tend = find(dat(:,1)==spl(2,1) & dat(:,2)==spl(2,2)); if isempty(tend), tend=size(dat,1); end
ysel = findstrings(data.names, txt(1,:));
data.y = dat(tbeg:tend, ysel);
data.w = ones(size(data.y,1),1);
data.time = linspace(ym2t(dat(tbeg,1:2)), ym2t(dat(tend,1:2)), size(data.y,1))';
clear d dat txt tbeg tend ysel

% check ydata for missing values, determine the sample
datatemp = checkdata(data, t2datestr, 1:data.Nm);
idspl = [t2datestr(datatemp.time(1)) '-' t2datestr(datatemp.time(end))];
clear datatemp

% output file names
fname = [pathout modname '_' strjoin(mnames,'_') '_' idspl '_' idscheme];
diary([fname '.txt'])
data = checkdata(data, t2datestr, 1:data.Nm); % again, for the diary
plot_y;

% print the correlation matrix of m
table = corr(data.y(:,1:data.Nm),'rows','pairwise');
in.cnames = strvcat(mnames);
in.rnames = strvcat(['correl.:' mnames]);
in.width = 200;
mprint(table,in)

% complete the minnesota prior
prior.minnesota.mvector = [zeros(data.Nm,1); nonst];

% replace NaNs with zeros in the initial condition
temp = data.y(1:prior.lags,:); temp(isnan(temp)) = 0; data.y(1:prior.lags,:) = temp; 

% drop the shocks before February 1994
%id = data.time<ym2t([1994 2])-1e-6; data.y(id,1:data.Nm) = NaN;

% estimate the VAR
%data.y(isnan(data.y)) = 0; res = VAR_dummyobsprior(data.y,data.w,gssettings.ndraws,prior);
res = VAR_withiid1kf(data, prior, gssettings);

savedata([fname '_data.csv'], data, t2ym)
%% identification
MAlags = 36;
N = length(data.names);

switch idscheme
    case 'chol'
        shocknames = data.names;
        irfs_draws = NaN(N,N,MAlags,gssettings.ndraws);
        for i = 1:gssettings.ndraws
            betadraw = res.beta_draws(1:end-size(data.w,2),:,i);
            sigmadraw = res.sigma_draws(:,:,i);
            response = impulsdtrf(reshape(betadraw',N,N,prior.lags), chol(sigmadraw), MAlags);
            irfs_draws(:,:,:,i) = response;
        end
        ss = 1;
        if length(mnames)>1 && ((~isempty(strfind(mnames{1},'neg')) && ~isempty(strfind(mnames{2},'pos'))) || ~isempty(strfind(mnames{2},'_signrestr'))), ss = 1:2; end
    case 'sgnm2' % baseline two sign restrictions
        shocknames = [{'mon.pol.', 'CBinfo'} mnames(2+1:end) ynames];
        dims = {[1 2]};
        imonpol = 1; inews = 2;
        test_restr = @(irfs)... %% restrictions by shock (i.e. by column):
            irfs(1,imonpol,1) > 0 && irfs(2,imonpol,1) < 0 &&... % mp
            irfs(1,inews,1) > 0 && irfs(2,inews,1) > 0; % cbi
        b_normalize = ones(1,N);
        max_try = 1000;
        disp(test_restr)
        irfs_draws = resirfssign(res, MAlags, dims, test_restr, b_normalize, max_try);
        %[irfs_draws, irfs_l_draws, irfs_u_draws] = resirfssign_robust(res, MAlags, dims, test_restr, b_normalize, max_try);
        ss = 1:2;
    case 'sgnm2strg' % strong instrument restriction
        % imposes that the THIRD variable goes up after mp shock
        shocknames = [{'mon.pol.', 'CBinfo'} ynames];
        dims = {[1 2]};
        iyld = 3;
        imonpol = 1; inews = 2;
        test_restr = @(irfs)... %% restrictions by shock (i.e. by column):
            irfs(1,imonpol,1) > 0 && irfs(2,imonpol,1) < 0 && irfs(iyld,imonpol,1)>0.01 &&... % mp
            irfs(1,inews,1) > 0 && irfs(2,inews,1) > 0; % cbi
        b_normalize = ones(1,N);
        max_try = 1000;
        disp(test_restr)
        irfs_draws = resirfssign(res, MAlags, dims, test_restr, b_normalize, max_try);
        ss = 1:2;
   case 'supdem' % disentangle CB info about supply and demand
        % requires: 1. interest rate; 2. stock price; 3. break-even inflation
        % CBinfosup shock moves stock price down but break-even inflation up
        shocknames = [{'mon.pol.', 'CBinfodem', 'CBinfosup'} mnames(3+1:end) ynames];
        dims = {[1 2 3]};
        imonpol = 1; inews = 2; isup = 3;
        test_restr = @(irfs)... %% restrictions by shock (i.e. by column):
            irfs(1,imonpol,1) > 0 && irfs(2,imonpol,1) < 0 && irfs(3,imonpol,1) < 0 &&... % mp
            irfs(1,inews,1) > 0 && irfs(2,inews,1) > 0 && irfs(3,inews,1) > 0 &&... % info demand
            irfs(1,isup,1) > -100 && irfs(2,isup,1) > 0 && irfs(3,isup,1) < 0; % info supply
        b_normalize = ones(N,1); b_normalize(3) = -1;
        max_try = 5000;
        disp(test_restr)
        irfs_draws = resirfssign(res, MAlags, dims, test_restr, b_normalize, max_try);
        ss = 1:3;
end

%% reporting (j&k 2020)

% report variance decompositon
vdec_mean = table_vdecomp(irfs_draws, 1:N, ss, data.names, shocknames, 24);

% report the irfs:
qtoplot = [0.5 0.16 0.84 0.05 0.95]; % quantiles to plot
varnames = [mnames, ynames]; varnames_nice = [mnames_nice ynames_nice]; shocknames_nice = shocknames;
ylimits = [];
%ylimits = [mylimits; yylimits];
transf = nan(N,2);

% print out the impact responses
table_irf(irfs_draws, ss, 1, varnames, qtoplot(1:3));
table_irf(irfs_draws, ss, 1, varnames, qtoplot([1 4 5]));

% plot the irfs validasi AS
hh = plot_irfs_draws(irfs_draws, data.Nm+1:min(N,data.Nm+ny1), ss, varnames_nice, varnames, shocknames_nice, idscheme, qtoplot, [0 0 1], '', ylimits, transf); align_Ylabels(hh); saveTightFigure(hh,[fname '_irfy1'],'pdf')
%hh = plot_irfs_draws(irfs_draws, data.Nm+ny1+1:min(N,data.Nm+2*ny1), ss, varnames_nice, varnames, shocknames_nice, idscheme, qtoplot, [0 0 1], '', ylimits); align_Ylabels(hh); saveTightFigure(hh,[fname '_irfy2'],'pdf')
hh = plot_irfs_draws(irfs_draws, 1:N, ss, varnames_nice, varnames, shocknames_nice, idscheme, qtoplot, [0 0 1], '', ylimits); align_Ylabels(hh); saveTightFigure(hh,[fname '_irfmy'],'pdf')

if 0 % save the ylimits
    hh = plot_irfs_draws(irfs_draws, 1:N, ss, varnames_nice, varnames, shocknames_nice, idscheme, qtoplot, [0 0 1], '', ylimits, transf); align_Ylabels(hh);
    ylimits = cell2mat(get(hh.Children,'Ylim')); ylimits = ylimits(1:max(ss):N*max(ss),:); ylimits = flipud(ylimits);
    save([fname '_ylimits.mat'],'ylimits');
end

if ~isempty(addvar)
    ylimits = [mylimits; yylimits];
    varstoplot = findstrings(addvar,varnames);
    hh = plot_irfs_draws(irfs_draws, varstoplot, ss, varnames_nice, varnames, shocknames_nice, idscheme, qtoplot, [0 0 1], '', ylimits);
    saveTightFigure(hh,[fname '_addvar'],'pdf')
end

if exist('irfs_l_draws','var')
credibility = [0.68 0.9];
hh = plot_irfs_draws_robust(irfs_draws, irfs_l_draws, irfs_u_draws, data.Nm+1:min(N,data.Nm+ny1), ss, varnames_nice, shocknames_nice, credibility, [0 0 1]); align_Ylabels(hh); saveTightFigure(hh,[fname '_rirfy1'],'pdf')
hh = plot_irfs_draws_robust(irfs_draws, irfs_l_draws, irfs_u_draws, data.Nm+ny1+1:N, ss, varnames_nice, shocknames_nice, credibility, [0 0 1]); align_Ylabels(hh); saveTightFigure(hh,[fname '_rirfy2'],'pdf')
%hh = plot_irfs_draws_robust(irfs_draws, irfs_l_draws, irfs_u_draws, 5:6, ss, varnames_nice, shocknames_nice, idscheme, credibility, [1 0 1]); align_Ylabels(hh); saveTightFigure(hh,[fname '_rirfyipcpi'],'pdf')
end

%% CUSTOM PLOTTING: GAYA JAROCINSKI & KARADI (DOUBLE BANDS 68% & 90%)
% Script ini mencetak 2 Figure terpisah dengan gaya persis J&K (2020).
% Fitur: Dua lapis area arsir (90% Light Grey + 68% Dark Grey).

% --- KONFIGURASI ---
horizon_plot = 35; 
idx_shocks = [1, 2]; % Shock 1 (Monetary) dan Shock 2 (Information)
shock_labels = {{'Guncangan Kebijakan Moneter','(pergerakan bersama negatif)'}, {'Guncangan Informasi Bank Sentral', '(pergerakan bersama positif)'}};

% Definisi Nama Variabel
var_titles_us = {{'Surprise','in federal fund futures'}, {'Surprise','in S&P 500'}};
var_titles_indo = {{'BI Rate','(persen)'}, {'1y IDN Bond Yield','(persen)'}, {'IHSG','(100 \times log)'}, {'Output','Industri (IPI)','(100 \times log)'}, {'Harga','Konsumen (IHK)','(100 \times log)'}};
%var_titles_indo = {{'1y IDN Bond Yield','(persen)'}, {'IHSG','(100 \times log)'}, {'Output','Industri (IPI)','(100 \times log)'}, {'Inflasi (IHK)','(100 \times log)'},{'BI Rate','(persen)'}};
var_titles = {{'Surprise','in federal fund','futures'}, {'Surprise','in S&P 500'}, {'BI Rate','(persen)'}, {'1y IDN Bond Yield','(persen)'}, {'IHSG','(100 \times log)'}, {'Output','Industri (IPI)','(100 \times log)'}, {'Harga','Konsumen (IHK)','(100 \times log)'}};
%var_titles = {{'Surprise','in federal fund','futures'},{'Surprise','in S&P 500'},{'1y IDN Bond Yield','(persen)'}, {'IHSG','(100 \times log)'}, {'Output','Industri (IPI)','(100 \times log)'}, {'Inflasi (IHK)','(100 \times log)'},{'BI Rate','(persen)'}};

%% --- BAGIAN 1: FIGURE A (VALIDASI IDENTIFIKASI - US VARIABLES) ---
% Layout: 2 Baris x 2 Kolom
figure('Name', 'Figure A - Identification Validation (J&K Style)', 'Color', 'w', 'Position', [100 100 800 600]);

idx_vars_us = [1, 2]; % Indeks variabel AS
plot_counter = 1;

for i = 1:length(idx_vars_us)
    for s = 1:length(idx_shocks)
        subplot(2, 2, plot_counter);
        hold on; grid on; axis tight;
        
        % --- AMBIL DATA ---
        var_idx = idx_vars_us(i);
        shock_idx = idx_shocks(s);
        
        % Ambil irfs_draws (hati-hati dengan dimensi horizon)
        % Kita ambil 1:(horizon_plot+1) agar mencakup bulan ke-0 sampai ke-14
        n_points = horizon_plot + 1;
        draws = squeeze(irfs_draws(var_idx, shock_idx, 1:n_points, :));
        
        % --- HITUNG PERCENTILES (J&K STYLE) ---
        med   = prctile(draws, 50, 2);  % Median (Garis Tengah)
        
        % Band Dalam (68% CI - Standard error 1 SD)
        low68 = prctile(draws, 16, 2);
        upp68 = prctile(draws, 84, 2);
        
        % Band Luar (90% CI - Standard error 1.645 SD)
        low90 = prctile(draws, 5, 2);
        upp90 = prctile(draws, 95, 2);
        
        % --- GAMBAR (LAYER BY LAYER) ---
        x = 0:(length(med)-1);
        
        % Layer 1: Band 90% (Warna Abu-abu Terang) - Digambar duluan agar di belakang
        fill([x, fliplr(x)], [low90', fliplr(upp90')], [0.90 0.90 0.90], 'EdgeColor', 'none');
        
        % Layer 2: Band 68% (Warna Abu-abu Lebih Gelap) - Digambar di atasnya
        fill([x, fliplr(x)], [low68', fliplr(upp68')], [0.70 0.70 0.70], 'EdgeColor', 'none');
        
        % Layer 3: Garis Median (Biru Tebal)
        plot(x, med, 'b-', 'LineWidth', 2); 
        
        % Layer 4: Garis Nol (Hitam Tipis)
        yline(0, 'k-', 'LineWidth', 0.5);   
        
        % --- FORMATTING ---
        if i == 1, title(shock_labels{s}, 'FontSize', 12, 'FontWeight', 'bold'); end
        if s == 1, ylabel(var_titles_us{i}, 'FontSize', 10, 'FontWeight', 'bold'); end
        
        % Anotasi Arah (Validasi)
        if s==1 && i==1, text(1, max(upp90), '\uparrow Rates', 'Color', 'b', 'FontSize', 8); end
        if s==1 && i==2, text(1, min(low90), '\downarrow Stocks', 'Color', 'b', 'FontSize', 8); end
        if s==2 && i==1, text(1, max(upp90), '\uparrow Rates', 'Color', 'b', 'FontSize', 8); end
        if s==2 && i==2, text(1, max(upp90), '\uparrow Stocks', 'Color', 'b', 'FontSize', 8); end
        
        set(gca, 'FontSize', 9, 'XLim', [0 horizon_plot], 'Layer', 'top'); % Layer top agar grid tidak tertutup
        plot_counter = plot_counter + 1;
    end
end
% Simpan Figure A
print(gcf, [fname '_FigA_Validation_JKStyle'], '-dpdf', '-bestfit');


%% REPORTING DAMPAK DOMESTIK - INDO VARIABLES) ---
% Layout: 5 Baris x 2 Kolom
figure('Name', 'Figure B - Indonesian Responses (J&K Style)', 'Color', 'w', 'Position', [100 50 800 1200]);

idx_vars_indo = [3, 4, 5, 6, 7]; % Indeks variabel Indonesia
plot_counter = 1;

for i = 1:length(idx_vars_indo)
    for s = 1:length(idx_shocks)
        subplot(5, 2, plot_counter);
        hold on; grid on; axis tight;
        
        % Ambil Data
        var_idx = idx_vars_indo(i);
        shock_idx = idx_shocks(s);
        
        n_points = horizon_plot + 1;
        draws = squeeze(irfs_draws(var_idx, shock_idx, 1:n_points, :));
        
        % Hitung Percentiles
        med   = prctile(draws, 50, 2);
        low68 = prctile(draws, 16, 2);
        upp68 = prctile(draws, 84, 2);
        low90 = prctile(draws, 5, 2);
        upp90 = prctile(draws, 95, 2);
        
        % Gambar
        x = 0:(length(med)-1);
        
        % Layer 1: Band 90% (Terang)
        fill([x, fliplr(x)], [low90', fliplr(upp90')], [0.90 0.90 0.90], 'EdgeColor', 'none');
        
        % Layer 2: Band 68% (Gelap)
        fill([x, fliplr(x)], [low68', fliplr(upp68')], [0.70 0.70 0.70], 'EdgeColor', 'none');
        
        % Layer 3: Garis Median (Merah Tebal untuk Indo)
        plot(x, med, 'r-', 'LineWidth', 1.5); 
        
        % Layer 4: Garis Nol
        yline(0, 'k-');
        
        % Judul & Label
        if i == 1, title(shock_labels{s}, 'FontSize', 11, 'FontWeight', 'bold'); end
        if s == 1, ylabel(var_titles_indo{i}, 'FontSize', 9, 'FontWeight', 'bold'); end
        
        set(gca, 'FontSize', 8, 'XLim', [0 horizon_plot], 'Layer', 'top');
        plot_counter = plot_counter + 1;
    end
end
% Simpan Figure B
print(gcf, [fname '_FigB_IndoResults_JKStyle'], '-dpdf', '-bestfit');
%% --- BAGIAN 3: FIGURE C - GABUNGAN SEMUA VARIABEL (FIX A4 + SUMBU X LENGKAP) ---
% Menggabungkan 2 variabel AS dan 5 variabel Indonesia di kertas A4

figure('Name', 'Figure C - Combined All Variables', 'Color', 'w');

% 1. PENGATURAN KERTAS A4 STANDAR (21 cm x 29.7 cm)
% Mengatur ukuran jendela di layar
set(gcf, 'Units', 'centimeters', 'Position', [2 2 19 27]); 

% Mengatur ukuran hasil cetak PDF agar persis A4 dengan margin
set(gcf, 'PaperUnits', 'centimeters');
set(gcf, 'PaperType', 'A4');
set(gcf, 'PaperOrientation', 'portrait');
set(gcf, 'PaperPositionMode', 'manual');
set(gcf, 'PaperPosition', [1 1 19 27.7]); % Lebar 19cm, Tinggi 27.7cm (Pas A4)

total_vars = 7; 
plot_counter = 1;

for i = 1:total_vars
    for s = 1:length(idx_shocks)
        subplot(total_vars, 2, plot_counter);
        hold on; grid on; axis tight;
        
        % --- AMBIL DATA ---
        shock_idx = idx_shocks(s);
        n_points = horizon_plot + 1;
        draws = squeeze(irfs_draws(i, shock_idx, 1:n_points, :)); 
        
        % --- HITUNG PERCENTILES ---
        med   = prctile(draws, 50, 2);
        low68 = prctile(draws, 16, 2);
        upp68 = prctile(draws, 84, 2);
        low90 = prctile(draws, 5, 2);
        upp90 = prctile(draws, 95, 2);
        
        % --- GAMBAR (LAYER BY LAYER) ---
        x = 0:(length(med)-1);
        
        % Layer Band 90% dan 68%
        fill([x, fliplr(x)], [low90', fliplr(upp90')], [0.90 0.90 0.90], 'EdgeColor', 'none');
        fill([x, fliplr(x)], [low68', fliplr(upp68')], [0.70 0.70 0.70], 'EdgeColor', 'none');
        
        % Layer Median: Garis Biru (AS) & Merah (Indonesia)
        if i <= 2
            plot(x, med, 'b-', 'LineWidth', 1.5); 
        else
            plot(x, med, 'r-', 'LineWidth', 1.5); 
        end
        
        % Layer Garis Nol
        yline(0, 'k-', 'LineWidth', 0.5);
        
        % --- FORMATTING & JUDUL ---
        % Tulis nama Shocks (Judul) HANYA di baris pertama
        if i == 1 
            title(shock_labels{s}, 'FontSize', 11, 'FontWeight', 'bold'); 
        end
        
        % Tulis nama Variabel HANYA di kolom kiri
        if s == 1 
            ylabel(var_titles{i}, 'FontSize', 8, 'FontWeight', 'bold'); 
        end
        
        % Pengaturan Sumbu: Font dibuat ukuran 8 agar rapi dan tidak memakan banyak tempat
        set(gca, 'FontSize', 8, 'XLim', [0 horizon_plot], 'Layer', 'top');
        plot_counter = plot_counter + 1;
    end
end

% 3. SIMPAN KE PDF (Tanpa -bestfit agar patuh pada ukuran manual A4)
print(gcf, [fname '_FigC_CombinedAll_A4_Style'], '-dpdf');
diary off

