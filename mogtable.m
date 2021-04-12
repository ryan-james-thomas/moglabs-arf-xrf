classdef mogtable < handle
    properties(SetAccess = protected)
        parent
        channel
        dataToWrite
        sync
    end
    
    properties
        t
        freq
        pow
        phase
    end
    
    properties(Constant)
        FREQ_BITS = 32;
        CLK = 1e3;  %In MHz, so 1 GHz
        MODE = 'TSB';
        POW_OFF_VALUE = -50;
        LOW_POW_THRESHOLD = -20;
    end
    
    methods
        function self = mogtable(parent,channel)
            if ~isa(parent,'mogdevice')
                error('Parent must be a ''mogdevice'' object!');
            end
            self.parent = parent;
            self.channel = channel;
            self.dataToWrite = [];
        end
        
        function self = check(self)
            if numel(self) > 1
                for nn = 1:numel(self)
                    self(nn).check;
                end
            else
                %Check times
    %             if any(diff(self.t) < 1e-6)
    %                 error('Time steps must be at least 1 us');
    %             end
                %Check frequencies
                if any(self.freq > 400) || any(self.freq < 10)
                    error('Frequencies must be between [10,400] MHz');
                end
                %Check powers
                if any(self.pow > 35.1)
                    error('Powers must be below 35.1 dBm');
                end
                %Coerce low powers
                self.pow(self.pow < self.LOW_POW_THRESHOLD) = self.POW_OFF_VALUE;
                %Wrap phase
                self.phase = mod(self.phase,360);
            end
        end
        
        function self = reduce(self,syncin)
            if nargin == 1
                syncin = [];
            end
            if numel(self) > 1
                for nn = 1:numel(self)
                    self(nn).reduce(syncin);
                end
            else
                self.check;
                self.dataToWrite = [self.t(1),self.pow(1),self.freq(1),self.phase(1)];
                N = numel(self.t);
                t2 = expand(self.t,N);
                p2 = expand(self.pow,N);
                f2 = expand(self.freq,N);
                ph2 = expand(self.phase,N);
                if ~isempty(syncin)
                    self.dataToWrite = [self.t(syncin),self.pow(syncin),self.freq(syncin),self.phase(syncin)];
                else
                    mm = 1;
                    self.sync = false(N,1);
                    self.sync(1) = true;
                    for nn = 2:N
%                         self.dataToWrite(mm+1,:) = [t2(nn),p2(nn),f2(nn),ph2(nn)];
%                         mm = mm + 1;
%                         self.sync(nn) = true;
                        if nn < N && p2(nn) >= self.LOW_POW_THRESHOLD && p2(nn+1) < self.LOW_POW_THRESHOLD
                            self.dataToWrite(mm+1,:) = [t2(nn),self.POW_OFF_VALUE,f2(nn),ph2(nn)];
                            mm = mm + 1;
                            self.sync(nn) = true;
                        elseif p2(nn) >= self.LOW_POW_THRESHOLD
                            self.dataToWrite(mm+1,:) = [t2(nn),p2(nn),f2(nn),ph2(nn)];
                            mm = mm + 1;
                            self.sync(nn) = true;
                        end
                    end
                end
            end
        end
        
        function s = createTableString(self)
            if numel(self) > 1
                s = {};
                for nn = 1:numel(self)
                    tmp = self(nn).createTableString;
                    s = [s tmp];
                end
            else
%                 self.reduce;
                dt = diff(self.dataToWrite(:,1));
                dt = round(dt(:)*1e6);
                dt(end+1) = 10; %#ok<*NASGU>
                N = numel(dt);
                if N > 8191
                    error('Maximum number of table entries is 8191');
                end

                s = cell(6 + N,1);
                s{1} = sprintf('mode,%d,%s',self.channel,self.MODE);
                s{2} = sprintf('debounce,%d,off',self.channel);
                s{3} = sprintf('table,stop,%d',self.channel);
                s{4} = sprintf('table,clear,%d',self.channel);
                
                for nn = 1:N
                    f = self.dataToWrite(nn,3);
                    p = self.dataToWrite(nn,2);
                    ph = self.dataToWrite(nn,4);
                    s{nn+4} = sprintf('table,append,%d,%.6f,%.4f,%.6f,%d',...
                        self.channel,f,p,ph,dt(nn));
                end
                s{end-1} = sprintf('table,arm,%d',self.channel);
                s{end} = sprintf('table,rearm,%d,on',self.channel);
            end
        end
        
        function numInstr = upload(self)
            commands = self.createTableString;
            commands = commands(:);
            for nn = 1:2
                commands{end+1} = sprintf('table,arm,%d',nn); %#ok<*AGROW>
                commands{end+1} = sprintf('table,rearm,%d,on',nn);
            end
            numInstr = numel(commands);
            self(1).parent.uploadCommands(commands(:));
        end
        
        function self = start(self)
            r = self.parent.cmd('table,start,%d',self.channel);
            disp(r);
        end
        
        function self = arm(self)
            if numel(self) > 1
                for nn = 1:numel(self)
                    self(nn).arm;
                end
            else
                self.parent.cmd('table,arm,%d',self.channel);
                self.parent.cmd('table,rearm,%d,on',self.channel);
            end
        end
        
    end
    
    methods(Static)
        function rf = opticalToRF(P,Pmax,rfmax)
            rf = (asin((P/Pmax).^0.25)*2/pi).^2*rfmax;
        end
    end
    
end

function r = expand(v,N)
    if numel(v) == 1
        r = v*ones(N,1);
    else
        r = v;
    end
end