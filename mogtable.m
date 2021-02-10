classdef mogtable < handle
    properties(SetAccess = protected)
        parent
        channel
        dataToWrite
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
        LOW_POW_THRESHOLD = -40;
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
                self.pow(self.pow < self.LOW_POW_THRESHOLD) = self.LOW_POW_THRESHOLD;
                %Wrap phase
                self.phase = mod(self.phase,360);
            end
        end
        
        function self = reduce(self)
            if numel(self) > 1
                for nn = 1:numel(self)
                    self(nn).reduce;
                end
            else
                powTh = 0;
                self.check;
                self.dataToWrite = [self.t(1),self.pow(1),self.freq(1),self.phase(1)];
                N = numel(self.t);
                t2 = expand(self.t,N);
                p2 = expand(self.pow,N);
                f2 = expand(self.freq,N);
                ph2 = expand(self.phase,N);
                mm = 1;
                for nn = 2:N
                    if p2(nn) >= powTh% || f2(nn) ~= f2(nn-1) || ph2(nn) ~= ph2(nn-1)
                        self.dataToWrite(mm+1,:) = [t2(nn),p2(nn),f2(nn),ph2(nn)];
                        mm = mm + 1;
                    end
                end
            end
        end
        
        function self = upload(self)
            if numel(self) > 1
                for nn = 1:numel(self)
                    self(nn).upload;
                end
            else
                self.reduce;
                self.parent.cmd('mode,%d,%s',self.channel,self.MODE);
                self.parent.cmd('table,clear,%d',self.channel);
                dt = diff(self.dataToWrite(:,1));
                dt = dt(:);
                dt(end+1) = 10e-6; %#ok<*NASGU>
                N = numel(dt);
                if N > 8191
                    error('Maximum number of table entries is 8191');
                end
                for nn = 1:N
                    f = self.dataToWrite(nn,3);
                    p = self.dataToWrite(nn,2);
                    ph = self.dataToWrite(nn,4);
                    self.parent.cmd('table,append,%d,%.6f,%.4f,%.6f,%d',...
                        self.channel,f,p,ph,round(dt(nn)*1e6));
                end
                self.parent.cmd('table,arm,%d',self.channel);
                self.parent.cmd('table,rearm,%d,on',self.channel);
            end
        end
        
        function self = start(self)
            r = self.parent.cmd('table,start,%d',self.channel);
            disp(r);
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