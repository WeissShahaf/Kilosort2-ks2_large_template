%% you need to change most of the paths in this block
%% setup parameters
starttime=datetime;
addpath(genpath('D:\sorters\KS\D:\sorters\KS\Kilosort2-ks2_large_template')) % path to kilosort folder


addpath(genpath('D:\sorters\KS\npy-matlab\npy-matlab'));
rootZ=cd;%'H:\scratch\GL1083_20210119_OF_g0\catgt_GL1083_20210119_OF_g0'
% rootZ = 'H:\scratch\GL1350_20230323_sleep_g0\catgt_GL1350_20230323_sleep_g0'; % the raw data binary file is in this folder
rootH = rootZ; rootZ0=rootZ;
pathToYourConfigFile = 'D:\sorters\KS\Kilosort2-ks2_large_template\configFiles'; % take from Github folder and put it somewhere else (together with the master_file)
chanMapFile = 'neuropix_NP1100_kilosortChanMap.mat';

ops.trange    = [0 Inf]; % time range to sort
ops.NchanTOT  = 385; % total number of channels in your recording

run(fullfile(pathToYourConfigFile, 'config_384_NP_UHD.m'))
ops.fproc       = fullfile(rootH, 'temp_wh.dat'); % proc file on a fast SSD
ops.chanMap = fullfile(pathToYourConfigFile, chanMapFile);
% ops.nNeighbors=32;
%% this block runs all the steps of the algorithm
fprintf('Looking for data inside %s \n', rootZ)

% is there a channel map file in this folder?
fs = dir(fullfile(rootZ, 'chan*.mat'));
%%
%get real opsfs
metafile = dir(fullfile(rootZ, '*ap.meta'));
if ~isempty(metafile)
meta=    meta2struct(metafile.name);
ops.fs=meta.imSampRate;
end
%%
if ~isempty(fs)
    ops.chanMap = fullfile(rootZ, fs(1).name);
end

% find the binary file
fs          = [dir(fullfile(rootZ, '*.bin')) dir(fullfile(rootZ, '*.dat'))];
if isempty(fs)
    error('no bin/dat file, check current folder')
end

ops.fbinary = fullfile(rootZ, fs(1).name);
%% skip filters if preprocessed
if contains(ops.fbinary,'catgt') || contains(ops.fbinary,'tcat') % no preprocessing - can increase batch size
    ops.doFilter=0;
    ops.CAR=0;
    ops.NT= 8*64*1024+ ops.ntbuff; % must be multiple of 32 + ntbuff. This is the batch size (try decreasing if out of memory). 
    ops.Parfor=0;
    ops=rmfield (ops,'fslow');
else% filter and CAR, at cost of batch size
    ops.doFilter=1;
    ops.CAR=1;
    ops.NT= 5*64*1024+ ops.ntbuff; % must be multiple of 32 + ntbuff. This is the batch size (try decreasing if out of memory). 
    ops.Parfor=1;
end
disp(ops)
% preprocess data to create temp_wh.dat
rez = preprocessDataSub(ops);

% time-reordering as a function of drift
rez = clusterSingleBatches(rez);

% saving here is a good idea, because the rest can be resumed after loading rez
save(fullfile(rootZ, 'rez.mat'), 'rez', '-v7.3');

% main tracking and template matching algorithm
rez = learnAndSolve8b(rez);

% final merges
rez = find_merges(rez, 1);

% final splits by SVD
rez = splitAllClusters(rez, 1);

% final splits by amplitudes
rez = splitAllClusters(rez, 0);

% decide on cutoff
rez = set_cutoff(rez);

fprintf('found %d good units \n', sum(rez.good>0))

% write to Phy
fprintf('Saving results to Phy  \n')
rezToPhy(rez, rootZ);

%% if you want to save the results to a Matlab file...

% discard features in final rez file (too slow to save)
% rez.cProj = [];
% rez.cProjPC = [];

% final time sorting of spikes, for apps that use st3 directly
[~, isort]   = sortrows(rez.st3);
rez.st3      = rez.st3(isort, :);

% save final results as rez2
fprintf('Saving final results in rez2  \n')
fname = fullfile(rootZ, 'rez2.mat');
save(fname, 'rez', '-v7.3');



rootZ = fullfile(rootZ0, 'kilosort2_hightemplate');
mkdir(rootZ)
rezToPhy2(rez, rootZ);


% save final results as rez2
fprintf('Saving final results in rez2  \n')
fname = fullfile(rootZ, 'rez2.mat');
save(fname, 'rez', '-v7.3');


fprintf('found %d good units \n', sum(rez.good>0))

%% remove duplicates
% addpath(genpath('D:\sorters\KS\Kilosort2_5\postProcess'))
rez = remove_ks2_duplicate_spikes(rez);
fprintf('found %d good units after removing duplicates \n', sum(rez.good>0))

rootZ = fullfile(rootZ0, 'Post_Dup_Rem');
mkdir(rootZ)
rezToPhy2(rez, rootZ);


% save final results as rez2
fprintf('Saving final results in rez2  \n')
fname = fullfile(rootZ, 'rez2.mat');
save(fname, 'rez', '-v7.3');

%% 
disp('')

endtime=datetime;
disp(endtime-starttime);
