clear all; 
close all; 
clear

tic
%Get all Matlab files from a directory
myDir = 'ENTER_PARENT_DIRECTORY HERE WITH PARTS OF SAMPLESERIES FILES';
file_all = dir(fullfile(myDir,'ABP*.mat'));
matfile = file_all([file_all.isdir] == 0); 
%To manually sort the record IDs....but doesn't look you have to!
    [~,index] = natsortrows({matfile.name}.'); 
    matfile = matfile(index);
clear file_all index

%Set blank arrays for loop to write into:
x=[];
data_qual_str=[];
data_qual_time=[];
time_vector=[];
measurement_data=[];

for k = 1:length(matfile)
  baseFileName = matfile(k).name; 
  fullFileName = fullfile(myDir, baseFileName);
  fprintf(1, 'Now reading %s\n', baseFileName);
  x=[x; load(fullFileName)];
  data_qual_str=horzcat(x(k, 1).data_qual_str,data_qual_str);
  data_qual_time=horzcat(x(k, 1).data_qual_time,data_qual_time);
  start_date_time=[x(1, 1).start_date_time];
    units=[x(1, 1).units];
    
  t=x(k,1).time_vector;
  d=x(k,1).measurement_data;
  
  %Now convert to date/time if desired...not strictly necessary
    tdatetime=seconds(t);
    %tdatetime.Format = 'hh:mm:ss.SSS';
    start = datetime(start_date_time,'InputFormat','dd MMM yyyy, HH:mm:ss.SSS','TimeZone','UTC');
    tstart = start + min(tdatetime);
    %tstart = start + tdatetime(1);
    %tstart.Format = 'MMM dd, yyyy HH:mm:ss.SSS','TimeZone','UTC';
    %ttimefromstart = tstart + tdatetime; 
    ttimefromstart = start + tdatetime; %add seconds to original start time
    %ttimefromstart.Format = 'MMM dd, yyyy HH:mm:ss.SSS','TimeZone','UTC';
    
%Create ttimefromstart just transpose to time
time = ttimefromstart.';
data = d;

TT = timetable(time,data);

%get sampling freq but if known sampling rate exists, use that...
    dt = median(diff(t));
    Fs = round(1 / dt); % Hz; has to be a positive integer or it freaks out

%Create the time series just using the "next" value to interpolate - this
%will mean gaps have a long list of exactly the same values:
try
    TT2 = retime(TT,'regular','next','SampleRate',125); 
catch errTT2
   if (strcmp(errTT2.identifier,'MATLAB:timetable:synchronize:NotUnique'))
      msg = ['There are duplicate row times when synchronizing...this might take longer...'];
        causeException = MException('MATLAB:myCode:dimensions',msg);
        errTT2 = addCause(errTT2,causeException);
   end
    %Find the unique set of times
    uniqueTimes = unique(TT.time);
    % retime all the data using this unique set
    TT = retime(TT,uniqueTimes,'mean');
    TT2 = retime(TT,'regular','next','SampleRate',500); 
end

%Now take that "next" series and find areas where there is no SD -> meaning
%there is sampling error for more than two samples -> this should create
%NaN in the same regular time series but 0 for data that HAS values
try
    TT3=retime(TT,'regular',@(data) std(data),'TimeStep',seconds(0.002),'IncludedEdge','right');
catch errTT3
    rethrow(errTT3)
end

%Combine the two so the NaNs represent actual missing data!
try
    TT2.data = TT2.data+TT3.data;
catch errComb
   if (strcmp(errComb.identifier,'MATLAB:dimagree'))
      msg = ['Dimensions do not agree: First argument has ', ...
            num2str(size(TT2,1)),' rows while second has ', ...
            num2str(size(TT3,1)),' rows.'];
        causeException = MException('MATLAB:myCode:dimensions',msg);
        errComb = addCause(errComb,causeException);
    end
   [a,i] = setdiff(TT2.time,TT3.time);
   TT2(1,:) = [];
   TT2.data = TT2.data+TT3.data;
end

%Create variables
timeList = TT2.(TT2.Properties.DimensionNames{1}); % or you can simply use TT.(name of your time column);
[timeList, index] = sort(timeList); %sort the timeList
timeInSeconds = [seconds(timeList - min(timeList)) + min(t)].'; %create seconds and transpose
dataList = TT2.data;

%If NaNs cause a problem because the program is weak and poorly written:
dataList(isnan(dataList))=0;

dataList = dataList(index); %sort the dataList

time_vector=horzcat(time_vector,timeInSeconds);
measurement_data=[measurement_data; dataList];

end

toc

%Save as a master Matlab file
FileName = [matfile(1,1).name(1:end-19),',Concat.mat'];
tic
save(FileName,'start_date_time','units','time_vector','measurement_data','data_qual_time','data_qual_str','-v7.3');
toc

%Now to put everything together with other data:

%Bring in some CNS 5-min numeric summaries averages from .txt file
tableNumSum = readtable('C:\Users\foremabo\OneDrive - University of Cincinnati\Desktop\ANIRI 179 Day 2\AllNumerics_SummaryData_inc5min.txt');

%Convert to date/time
start = datetime(start_date_time,'InputFormat','dd MMM yyyy, HH:mm:ss.SSS','Format','dd MMM yyyy');
tableNumSum.Day_ = start + tableNumSum.Day_;
tableNumSum.Day_ = dateshift(tableNumSum.Day_, 'start', 'day');
tableNumSum.ClockTime = datetime(tableNumSum.ClockTime,'InputFormat','HH:mm','Format','HH:mm');
tableNumSum.Time = tableNumSum.Day_ + timeofday(tableNumSum.ClockTime);
tableNumSum.Time.Format ='dd MMM yyyy HH:mm';

tableNumSum= removevars(tableNumSum,{'Day_','ClockTime'});
tableNumSum = movevars(tableNumSum,'Time','Before','ABP_Syst_Numeric_Float_IntelliVue_mmHg__Mean');
timetableNumSum=table2timetable(tableNumSum);
timetableNumSum.Time = dateshift(timetableNumSum.Time, 'start', 'minute');
timetableNumSum.Time.Format = 'dd MMM yyyy, HH:mm:ss:SSS';
head(timetableNumSum,3)

%Bring in the HRV data from .txt file
hrvfile = 'C:\Users\foremabo\OneDrive - University of Cincinnati\Desktop\ANIRI 179 Day 2\HRVseq_5min_ECG,II,SampleSeries,Integer,IntelliVue,Concat.TXT'
opts = detectImportOptions(hrvfile, 'NumHeaderLines', 2, 'Delimiter',{'\t'});
opts.Delimiter
opts.PreserveVariableNames = true; 
opts.VariableNames = {'Filename','Epoch duration','Analyszed duration','Epoch nb','H beginning','H end','nb RR','n beginning','n end','RR','HR','pNN20','pNN30','pNN50','SDNN','RMSSD','X','Y','N','M','IndTri','TINN','PSD type','Detrend spectrum(PSD)','Fr(PSD)','Bandwidth(PSD)','[VLF](PSD)','[LF](PSD)','[HF](PSD)','Ptot','VLF','LF','HF','LFnu','HFnu','LF/HF','centroid','SD1','SD2','SD1/SD2','SD1nu','SD2nu','Skewness','Kurtosis','m(Lyapunov)','t(Lyapunov)','T(Lyapunov)','Smax(Lyapunov)','Smin(Lyapunov)','thmax(Lyapunov)','Larg. Lyapunov Exp.','pLF1','pLF2','pHF1','pHF2','IMAI1','IMAI2','Short term n1(DFA)','Long term n2(DFA)','\alpha1(DFA)','\alpha2(DFA)','H(DFA)','H(Katz)','Kmax(Higuchi)','H(Higuchi)','H(Hurst)','m(AppEn)','r(AppEn)','AppEn','m(SampEn)','r(SampEn)','SamEn','SE','CE','CCE','NCCE','\rho','LZC','Xi(Symbolic)','L(Symbolic)','0V','0V%','1V','1V%','2LV','2LV%','2UV','2UV%','MP','M%'}
%opts.VariableNamesLine = 1;
%opts.VariableUnitsLine = 2;
preview(hrvfile,opts)
tableHRV = readtable(hrvfile,opts);
tableHRV= removevars(tableHRV,{'ExtraVar1'});

startHRV = datetime(start_date_time,'InputFormat','dd MMM yyyy, HH:mm:ss.SSS','Format','dd MMM yyyy, HH:mm');
%tableHRV.Time = startHRV + tableHRV.('H end')
tableHRV.Time = startHRV + (tableHRV.('Epoch nb').*tableHRV.('Analyszed duration'));
tableHRV = movevars(tableHRV,'Time','Before','Filename');
timetableHRV=table2timetable(tableHRV);
timetableHRV.Time = dateshift(timetableHRV.Time, 'start', 'minute');
timetableHRV.Time.Format = 'dd MMM yyyy, HH:mm:ss:SSS';

joinAll = outerjoin(timetableNumSum,timetableHRV,'MergeKeys',true);